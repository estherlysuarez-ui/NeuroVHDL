-- ============================================================
-- Modulo: conv_relu.vhd
-- Descripcion: Capa convolucional 3x3, 8 filtros, padding=same
--              sobre imagen 28x28 en escala de grises (1 canal).
--
--  Pipeline:
--    1. Registro de desplazamiento (shift-reg) 3 lineas x 28
--       -> ventana 3x3 disponible cada ciclo
--    2. 8 MACs en paralelo (uno por filtro)
--    3. Suma sesgo (bias) y ReLU
--    4. Registro acumulador -> salida Q1.7 (8 bits)
--
--  Pesos almacenados en ROMs inicializadas con package pkg.
--  Conv1 pesos: 3x3x1x8 = 72 bytes
-- ============================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Package generado por Python (se copia al proyecto Quartus)
-- use work.conv1_pkg.all;

entity conv_relu is
    generic (
        IMG_W    : integer := 28;
        N_FILT   : integer := 8;    -- numero de filtros
        FRAC     : integer := 7     -- bits fraccion Q1.7
    );
    port (
        clk       : in  std_logic;
        reset     : in  std_logic;
        en        : in  std_logic;
        pixel_in  : in  signed(7 downto 0);   -- pixel Q0.8 de entrada
        valid_in  : in  std_logic;
        -- salidas: N_FILT canales Q1.7
        conv_out  : out signed(7 downto 0);   -- mux secuencial de filtros
        filt_idx  : out std_logic_vector(2 downto 0);  -- que filtro sale
        valid_out : out std_logic;
        done      : out std_logic
    );
end entity;

architecture rtl of conv_relu is

    -- ── Tipos ───────────────────────────────────────────────
    type t_kernel  is array(0 to 8)  of signed(7 downto 0);  -- 9 pesos/filtro
    type t_kernels is array(0 to 7)  of t_kernel;            -- 8 filtros
    type t_bias    is array(0 to 7)  of signed(7 downto 0);
    type t_sreg    is array(0 to 2*IMG_W+2) of signed(7 downto 0); -- 3 lineas

    -- ── Pesos: llenar con valores del Python export ──────────
    -- PLACEHOLDER: sustituir por constantes del *_pkg.vhd
    -- Estos valores de ejemplo se sobreescriben al importar el pkg
-- ── Pesos y Sesgos ───────────────────────────────────────────
    constant KERN : t_kernels := (
        0 => (to_signed(-18,8), to_signed(45,8), to_signed(-71,8), to_signed(21,8), to_signed(-13,8), to_signed(-12,8), to_signed(41,8), to_signed(-23,8), to_signed(33,8)),
        1 => (to_signed(-38,8), to_signed(-107,8), to_signed(53,8), to_signed(-112,8), to_signed(-27,8), to_signed(15,8), to_signed(20,8), to_signed(-4,8), to_signed(-11,8)),
        2 => (to_signed(-128,8), to_signed(-21,8), to_signed(-33,8), to_signed(22,8), to_signed(28,8), to_signed(30,8), to_signed(22,8), to_signed(48,8), to_signed(-20,8)),
        3 => (to_signed(52,8), to_signed(89,8), to_signed(-62,8), to_signed(12,8), to_signed(28,8), to_signed(27,8), to_signed(34,8), to_signed(16,8), to_signed(5,8)),
        4 => (to_signed(-27,8), to_signed(26,8), to_signed(10,8), to_signed(47,8), to_signed(44,8), to_signed(-22,8), to_signed(1,8), to_signed(27,8), to_signed(-95,8)),
        5 => (to_signed(60,8), to_signed(-33,8), to_signed(-40,8), to_signed(16,8), to_signed(4,8), to_signed(92,8), to_signed(26,8), to_signed(77,8), to_signed(41,8)),
        6 => (to_signed(26,8), to_signed(47,8), to_signed(8,8), to_signed(16,8), to_signed(90,8), to_signed(24,8), to_signed(61,8), to_signed(56,8), to_signed(43,8)),
        7 => (to_signed(-7,8), to_signed(30,8), to_signed(53,8), to_signed(66,8), to_signed(-33,8), to_signed(-21,8), to_signed(-1,8), to_signed(36,8), to_signed(-64,8))
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

    -- ── Registro de desplazamiento (line buffer) ─────────────
    signal sreg        : t_sreg := (others => (others => '0'));

    -- ── Ventana 3x3 ─────────────────────────────────────────
    type t_win is array(0 to 8) of signed(7 downto 0);
    signal win : t_win;

    -- ── Contadores ──────────────────────────────────────────
    signal cnt_pix   : unsigned(9 downto 0) := (others => '0'); -- 0..783
    signal cnt_filt  : unsigned(2 downto 0) := (others => '0'); -- 0..7
    signal r_valid   : std_logic := '0';
    signal r_done    : std_logic := '0';

    -- ── Acumulador MAC (un MAC secuencial por filtro) ────────
    signal mac_acc   : signed(23 downto 0) := (others => '0');
    signal mac_cnt   : unsigned(3 downto 0) := (others => '0'); -- 0..8
    signal phase     : std_logic_vector(1 downto 0) := "00";
    -- phase: "00"=idle, "01"=mac, "10"=bias+relu, "11"=output

    signal r_out     : signed(7 downto 0) := (others => '0');
    signal r_fidx    : std_logic_vector(2 downto 0) := (others => '0');

    -- ── Componentes ─────────────────────────────────────────
    component mult_add
        port (clk,reset,en,clr : in std_logic;
              a,b : in signed(7 downto 0);
              acc : out signed(23 downto 0));
    end component;

    component comparador
        generic (N : integer);
        port (a,b : in signed(N-1 downto 0);
              mayor,igual : out std_logic;
              relu : out signed(N-1 downto 0));
    end component;

    signal mac_en    : std_logic := '0';
    signal mac_clr   : std_logic := '0';
    signal mac_a     : signed(7 downto 0) := (others => '0');
    signal mac_b     : signed(7 downto 0) := (others => '0');
    signal mac_result: signed(23 downto 0);

    signal relu_in   : signed(7 downto 0);
    signal relu_out  : signed(7 downto 0);
    signal dummy_m, dummy_i : std_logic;

begin

    -- ── MAC unit ─────────────────────────────────────────────
    U_MAC : mult_add
        port map (clk=>clk, reset=>reset, en=>mac_en, clr=>mac_clr,
                  a=>mac_a, b=>mac_b, acc=>mac_result);

    -- ── ReLU ─────────────────────────────────────────────────
    relu_in <= mac_result(14 downto 7);  -- truncar a Q1.7 (>> 7)
    U_RELU : comparador
        generic map (N => 8)
        port map (a=>relu_in, b=>to_signed(0,8),
                  mayor=>dummy_m, igual=>dummy_i, relu=>relu_out);

    -- ── Registro de desplazamiento (shift buffer 3 lineas) ───
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                sreg <= (others => (others => '0'));
            elsif valid_in = '1' then
                -- desplazar e insertar nuevo pixel
                for i in sreg'length-1 downto 1 loop
                    sreg(i) <= sreg(i-1);
                end loop;
                sreg(0) <= pixel_in;
            end if;
        end if;
    end process;

    -- ── Ventana 3x3 desde el shift register ─────────────────
    -- posiciones del buffer: actual, +28, +56 (3 filas)
    win(0) <= sreg(0);         win(1) <= sreg(1);         win(2) <= sreg(2);
    win(3) <= sreg(IMG_W);     win(4) <= sreg(IMG_W+1);   win(5) <= sreg(IMG_W+2);
    win(6) <= sreg(2*IMG_W);   win(7) <= sreg(2*IMG_W+1); win(8) <= sreg(2*IMG_W+2);

    -- ── Control MAC secuencial: 9 ciclos por filtro, 8 filtros
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                mac_cnt  <= (others => '0');
                cnt_filt <= (others => '0');
                cnt_pix  <= (others => '0');
                phase    <= "00";
                r_valid  <= '0';
                r_done   <= '0';
                mac_en   <= '0';
                mac_clr  <= '0';
            else
                mac_clr  <= '0';
                r_valid  <= '0';

                case phase is
                    -- Esperar pixel valido ─────────────────────────────────
                    when "00" =>
                        if valid_in = '1' and
                           cnt_pix >= to_unsigned(2*IMG_W+2, 10) then
                            -- ventana lista: iniciar MAC para filtro cnt_filt
                            mac_clr  <= '1';
                            mac_cnt  <= (others => '0');
                            mac_en   <= '1';
                            phase    <= "01";
                        end if;
                        if valid_in = '1' then
                            if cnt_pix = 783 then
                                cnt_pix <= (others => '0');
                            else
                                cnt_pix <= cnt_pix + 1;
                            end if;
                        end if;

                    -- Fase MAC: 9 multiplicaciones ─────────────────────────
                    when "01" =>
                        mac_a <= win(to_integer(mac_cnt));
                        mac_b <= KERN(to_integer(cnt_filt))
                                     (to_integer(mac_cnt));
                        if mac_cnt = 8 then
                            mac_en  <= '0';
                            phase   <= "10";
                            mac_cnt <= (others => '0');
                        else
                            mac_cnt <= mac_cnt + 1;
                        end if;

                    -- Suma sesgo y truncado ────────────────────────────────
                    when "10" =>
                        -- relu_out ya tiene el resultado (1 ciclo latencia)
                        r_out   <= relu_out;
                        r_fidx  <= std_logic_vector(cnt_filt);
                        r_valid <= '1';
                        if cnt_filt = 7 then
                            cnt_filt <= (others => '0');
                            phase    <= "00";
                            -- avanzar pixel para siguiente ventana
                            if cnt_pix = 784 then
                                r_done <= '1';
                            end if;
                        else
                            cnt_filt <= cnt_filt + 1;
                            mac_clr  <= '1';
                            mac_cnt  <= (others => '0');
                            mac_en   <= '1';
                            phase    <= "01";
                        end if;

                    when others => phase <= "00";
                end case;
            end if;
        end if;
    end process;

    conv_out  <= r_out;
    filt_idx  <= r_fidx;
    valid_out <= r_valid;
    done      <= r_done;

end architecture;
