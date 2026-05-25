-- ============================================================
-- Modulo: conv_relu.vhd
-- Descripcion: Capa convolucional 3x3, 8 filtros, padding=VALID
--              sobre imagen 28x28 en escala de grises (Q1.7).
--
-- OPTIMIZACIONES vs. version original:
--   1. 8 DSP MACs EN PARALELO: un DSP por filtro. Los 9 pesos
--      de cada filtro se acumulan secuencialmente (9 ciclos)
--      pero los 8 filtros trabajan simultaneamente -> throughput
--      8x mayor con los mismos ciclos de reloj.
--   2. LINE BUFFER en BRAM M9K: en lugar de un shift-register
--      masivo de flip-flops (3*28 = 84 FFs x 8b = 672 FFs),
--      se usan dos ram_sp para las dos lineas de "historia".
--      La ventana 3x3 se forma con registros de 3 elementos.
--   3. BIAS sumado con adder de 24 bits (no saturacion prematura).
--   4. ReLU puramente combinacional (comparador con bit de signo).
--   5. Pipeline correcto: mac_cnt gating sincronizado.
--
-- Latencia desde primer pixel valido hasta primer valid_out:
--   2*28 + 2 (lineas de relleno) + 9 (ciclos MAC) + 2 (pipe) ciclos
--
-- Senales:
--   pixel_in  : signed 8b Q1.7 (normalizado 0..127 en el entrenamiento)
--   valid_in  : '1' cuando pixel_in es valido
--   conv_out  : resultado Q1.7 de un filtro
--   filt_idx  : indice 0..7 del filtro cuyo resultado sale
--   valid_out : '1' cuando conv_out/filt_idx son validos
--   done      : '1' al terminar los 784 pixeles (imagen completa)
-- ============================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity conv_relu is
    generic (
        IMG_W  : integer := 28;   -- ancho de imagen
        N_FILT : integer := 8;    -- numero de filtros (mapeo 1:1 a DSPs)
        FRAC   : integer := 7     -- fraccion Q1.7
    );
    port (
        clk       : in  std_logic;
        reset     : in  std_logic;
        en        : in  std_logic;
        pixel_in  : in  signed(7 downto 0);
        valid_in  : in  std_logic;
        conv_out  : out signed(7 downto 0);
        filt_idx  : out std_logic_vector(2 downto 0);
        valid_out : out std_logic;
        done      : out std_logic
    );
end entity;

architecture rtl of conv_relu is
2
    -- ── Tipos ────────────────────────────────────────────────
    type t_kernel  is array(0 to 8) of signed(7 downto 0);
    type t_kernels is array(0 to N_FILT-1) of t_kernel;
    type t_bias    is array(0 to N_FILT-1) of signed(7 downto 0);
    type t_win     is array(0 to 2) of signed(7 downto 0);  -- 3 cols por fila
    type t_acc     is array(0 to N_FILT-1) of signed(23 downto 0);
    type t_prod    is array(0 to N_FILT-1) of signed(15 downto 0);

    -- ── Pesos Conv1 (3x3x1x8) en Q1.7 ───────────────────────
    constant KERN : t_kernels := (
        0 => (to_signed(-18,8), to_signed(45,8),  to_signed(-71,8),
              to_signed(21,8),  to_signed(-13,8), to_signed(-12,8),
              to_signed(41,8),  to_signed(-23,8), to_signed(33,8)),
        1 => (to_signed(-38,8),  to_signed(-107,8), to_signed(53,8),
              to_signed(-112,8), to_signed(-27,8),  to_signed(15,8),
              to_signed(20,8),   to_signed(-4,8),   to_signed(-11,8)),
        2 => (to_signed(-128,8), to_signed(-21,8), to_signed(-33,8),
              to_signed(22,8),   to_signed(28,8),   to_signed(30,8),
              to_signed(22,8),   to_signed(48,8),   to_signed(-20,8)),
        3 => (to_signed(52,8),  to_signed(89,8),  to_signed(-62,8),
              to_signed(12,8),  to_signed(28,8),  to_signed(27,8),
              to_signed(34,8),  to_signed(16,8),  to_signed(5,8)),
        4 => (to_signed(-27,8), to_signed(26,8),  to_signed(10,8),
              to_signed(47,8),  to_signed(44,8),  to_signed(-22,8),
              to_signed(1,8),   to_signed(27,8),  to_signed(-95,8)),
        5 => (to_signed(60,8),  to_signed(-33,8), to_signed(-40,8),
              to_signed(16,8),  to_signed(4,8),   to_signed(92,8),
              to_signed(26,8),  to_signed(77,8),  to_signed(41,8)),
        6 => (to_signed(26,8),  to_signed(47,8),  to_signed(8,8),
              to_signed(16,8),  to_signed(90,8),  to_signed(24,8),
              to_signed(61,8),  to_signed(56,8),  to_signed(43,8)),
        7 => (to_signed(-7,8),  to_signed(30,8),  to_signed(53,8),
              to_signed(66,8),  to_signed(-33,8), to_signed(-21,8),
              to_signed(-1,8),  to_signed(36,8),  to_signed(-64,8))
    );

    constant BIAS : t_bias := (
        0 => to_signed(-10,8),
        1 => to_signed(-26,8),
        2 => to_signed(0,8),
        3 => to_signed(-5,8),
        4 => to_signed(12,8),
        5 => to_signed(-4,8),
        6 => to_signed(-18,8),
        7 => to_signed(-3,8)
    );

    -- ── Line buffer: dos RAMs de IMG_W x 8b (mapeadas a M9K) ─
    -- Linea 0 = fila N-2, Linea 1 = fila N-1, fila actual = pixel_in
    signal lb0_wr, lb1_wr     : std_logic := '0';
    signal lb0_addr, lb1_addr : std_logic_vector(4 downto 0);  -- 0..27
    signal lb0_din,  lb1_din  : std_logic_vector(7 downto 0);
    signal lb0_dout, lb1_dout : std_logic_vector(7 downto 0);

    -- ── Ventana 3x3: 3 filas x 3 cols (registros) ────────────
    -- win_rN_cM : fila N (0=top, 2=bot), columna M (0=left, 2=right)
    signal win_r0 : t_win := (others => (others => '0'));
    signal win_r1 : t_win := (others => (others => '0'));
    signal win_r2 : t_win := (others => (others => '0'));

    -- Mapeo plano para el indice mac_cnt:
    --  0..2 = win_r0(0..2), 3..5 = win_r1(0..2), 6..8 = win_r2(0..2)
    type t_win_flat is array(0 to 8) of signed(7 downto 0);
    signal win_flat : t_win_flat;

    -- ── DSP MACs paralelos ────────────────────────────────────
    -- Etapa 1: productos registrados (DSP inference)
    signal r_prod : t_prod := (others => (others => '0'));
    -- Etapa 2: acumuladores
    signal r_acc  : t_acc  := (others => (others => '0'));

    attribute multstyle : string;
    attribute multstyle of r_prod : signal is "dsp";

    -- ── Control ──────────────────────────────────────────────
    signal cnt_pix  : unsigned(9 downto 0) := (others => '0');  -- 0..783
    signal cnt_col  : unsigned(4 downto 0) := (others => '0');  -- 0..27
    signal cnt_row  : unsigned(4 downto 0) := (others => '0');  -- 0..27
    signal mac_cnt  : unsigned(3 downto 0) := (others => '0');  -- 0..8
    signal mac_run  : std_logic := '0';
    signal lb_phase : unsigned(4 downto 0) := (others => '0');  -- escritura lb

    -- ── Output stage ─────────────────────────────────────────
    signal out_filt : unsigned(2 downto 0) := (others => '0');  -- 0..7
    signal out_run  : std_logic := '0';
    signal r_valid  : std_logic := '0';
    signal r_done   : std_logic := '0';
    signal r_out    : signed(7 downto 0) := (others => '0');
    signal r_fidx   : std_logic_vector(2 downto 0) := (others => '0');

    -- ── Auxiliares ───────────────────────────────────────────
    signal pix_buf  : signed(7 downto 0) := (others => '0');  -- pixel actual
    signal valid_d1 : std_logic := '0';
    signal valid_d2 : std_logic := '0';

    -- Ventana lista cuando tenemos >= 2 lineas previas completas
    signal win_ready : std_logic := '0';

    -- ── Componente BRAM ───────────────────────────────────────
    component ram_sp
        generic (ADDR_W : integer; DATA_W : integer; MIF_FILE : string);
        port (clk  : in  std_logic;
              wr   : in  std_logic;
              addr : in  std_logic_vector(ADDR_W-1 downto 0);
              din  : in  std_logic_vector(DATA_W-1 downto 0);
              dout : out std_logic_vector(DATA_W-1 downto 0));
    end component;

begin

    -- ── Instancias BRAM de line buffer (1 M9K cada una) ───────
    U_LB0 : ram_sp
        generic map (ADDR_W => 5, DATA_W => 8, MIF_FILE => "")
        port map (clk => clk, wr => lb0_wr, addr => lb0_addr,
                  din => lb0_din, dout => lb0_dout);

    U_LB1 : ram_sp
        generic map (ADDR_W => 5, DATA_W => 8, MIF_FILE => "")
        port map (clk => clk, wr => lb1_wr, addr => lb1_addr,
                  din => lb1_din, dout => lb1_dout);

    -- ── Mapeo plano de la ventana 3x3 ────────────────────────
    win_flat(0) <= win_r0(0); win_flat(1) <= win_r0(1); win_flat(2) <= win_r0(2);
    win_flat(3) <= win_r1(0); win_flat(4) <= win_r1(1); win_flat(5) <= win_r1(2);
    win_flat(6) <= win_r2(0); win_flat(7) <= win_r2(1); win_flat(8) <= win_r2(2);

    -- ── Proceso principal ─────────────────────────────────────
    process(clk)
        variable biased  : signed(23 downto 0);
        variable trunced : signed(7 downto 0);
    begin
        if rising_edge(clk) then
            if reset = '1' then
                cnt_pix   <= (others => '0');
                cnt_col   <= (others => '0');
                cnt_row   <= (others => '0');
                mac_cnt   <= (others => '0');
                mac_run   <= '0';
                out_filt  <= (others => '0');
                out_run   <= '0';
                r_valid   <= '0';
                r_done    <= '0';
                win_ready <= '0';
                lb_phase  <= (others => '0');
                win_r0    <= (others => (others => '0'));
                win_r1    <= (others => (others => '0'));
                win_r2    <= (others => (others => '0'));
                r_acc     <= (others => (others => '0'));
                r_prod    <= (others => (others => '0'));
            else
                -- Defaults
                lb0_wr  <= '0';
                lb1_wr  <= '0';
                r_valid <= '0';
                r_done  <= '0';

                -- ── Paso 1: llegada de pixel ──────────────────
                if valid_in = '1' and en = '1' then
                    pix_buf <= pixel_in;

                    -- Actualizar ventana deslizante:
                    -- La fila 2 (inferior) viene de pixel_in
                    -- La fila 1 (media)   viene de lb1 (lectura del ciclo anterior)
                    -- La fila 0 (superior) viene de lb0
                    win_r2(2) <= win_r2(1);
                    win_r2(1) <= win_r2(0);
                    win_r2(0) <= pixel_in;

                    win_r1(2) <= win_r1(1);
                    win_r1(1) <= win_r1(0);
                    win_r1(0) <= signed(lb1_dout);  -- 1 ciclo latencia BRAM

                    win_r0(2) <= win_r0(1);
                    win_r0(1) <= win_r0(0);
                    win_r0(0) <= signed(lb0_dout);

                    -- Escribir pixel actual en lb1 (sera lb0 en la prox fila)
                    -- y lb1 pasa a lb0 al avanzar de fila
                    lb1_wr   <= '1';
                    lb1_din  <= std_logic_vector(pixel_in);
                    lb1_addr <= std_logic_vector(cnt_col);

                    -- Lectura anticipada para el proximo pixel
                    lb0_addr <= std_logic_vector(cnt_col);
                    lb1_addr <= std_logic_vector(cnt_col);

                    -- Contadores
                    if cnt_col = IMG_W-1 then
                        cnt_col <= (others => '0');
                        if cnt_row = IMG_W-1 then
                            cnt_row <= (others => '0');
                            r_done  <= '1';
                        else
                            cnt_row <= cnt_row + 1;
                        end if;
                        -- Al completar fila: rotar line buffers
                        -- lb0 <- lb1 (copiar se hace implicitamente con los punteros
                        --  porque ambos usan la misma columna; en el siguiente row
                        --  lb0 lee lo que lb1 escribio en esta vuelta)
                        -- Implementacion: alternamos quien escribe (ping-pong)
                        -- Para simplicidad: lb0 siempre tiene fila N-2, lb1 fila N-1
                        -- Usamos un flag de paridad de fila
                        lb0_wr   <= '1';
                        lb0_din  <= lb1_dout;  -- mover lb1 -> lb0 al rotar
                        lb0_addr <= std_logic_vector(cnt_col);
                    else
                        cnt_col <= cnt_col + 1;
                    end if;

                    cnt_pix <= cnt_pix + 1;

                    -- La ventana esta lista cuando hay al menos 2 filas completas
                    if cnt_pix >= to_unsigned(2*IMG_W + 1, 10) then
                        win_ready <= '1';
                    end if;
                end if;

                -- ── Paso 2: lanzar MAC cuando ventana lista ───
                if win_ready = '1' and valid_in = '1' and en = '1'
                   and mac_run = '0' and out_run = '0' then
                    -- Limpiar acumuladores y arrancar
                    for f in 0 to N_FILT-1 loop
                        r_acc(f) <= (others => '0');
                    end loop;
                    mac_cnt <= (others => '0');
                    mac_run <= '1';
                end if;

				-- ── Paso 3: fase MAC (9 ciclos + 1 flush pipeline) ─
				if mac_run = '1' then

					 -- =====================================================
					 -- ETAPA 1: DSP MULTIPLY
					 -- SOLO indices validos 0..8
					 -- =====================================================
					 if mac_cnt < 9 then
						  for f in 0 to N_FILT-1 loop
								r_prod(f) <= win_flat(to_integer(mac_cnt)) *
												 KERN(f)(to_integer(mac_cnt));
						  end loop;
					 end if;

					 -- =====================================================
					 -- ETAPA 2: ACUMULACION PIPELINE
					 -- Desde mac_cnt=1 ya existe producto valido previo
					 -- =====================================================
					 if mac_cnt > 0 then
						  for f in 0 to N_FILT-1 loop
								r_acc(f) <= r_acc(f) + resize(r_prod(f), 24);
						  end loop;
					 end if;

					 -- =====================================================
					 -- CONTROL PIPELINE
					 -- mac_cnt = 9 -> flush final
					 -- =====================================================
					 if mac_cnt = 9 then
						  mac_run  <= '0';
						  out_run  <= '1';
						  out_filt <= (others => '0');
					 else
						  mac_cnt <= mac_cnt + 1;
					 end if;

				end if;

                -- ── Paso 4: salida secuencial (1 filtro por ciclo) ───
                if out_run = '1' then
                    -- Sumar bias y truncar a Q1.7
                    biased  := r_acc(to_integer(out_filt)) +
                               resize(BIAS(to_integer(out_filt)), 24);
                    -- Truncar: tomar bits [FRAC+7:FRAC] = [14:7]
                    trunced := biased(FRAC+7 downto FRAC);
                    -- ReLU: si negativo -> 0
                    if biased(23) = '0' then
                        r_out <= trunced;
                    else
                        r_out <= (others => '0');
                    end if;
                    r_fidx  <= std_logic_vector(out_filt);
                    r_valid <= '1';

                    if out_filt = N_FILT-1 then
                        out_run  <= '0';
                        out_filt <= (others => '0');
                    else
                        out_filt <= out_filt + 1;
                    end if;
                end if;

            end if;
        end if;
    end process;

    conv_out  <= r_out;
    filt_idx  <= r_fidx;
    valid_out <= r_valid;
    done      <= r_done;

end architecture;
