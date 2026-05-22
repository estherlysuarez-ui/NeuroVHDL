-- ============================================================
-- Modulo: salida_clasificacion.vhd
-- Descripcion: Capa FC2 (64->10) + argmax para clasificacion.
--
-- CORRECCIONES vs. version original:
--   1. max_val se inicializa al minimo signed de 24 bits
--      (x"800000") para que el PRIMER resultado siempre se
--      capture. El codigo original usaba (23=>'1',others=>'0')
--      que es exactamente ese valor, PERO la comparacion usaba
--      cmp_mayor (a > b), que con max_val=MIN_SIGNED seria
--      siempre verdadero la primera vez -> CORRECTO conceptualmente,
--      pero el comparador tenia N=24 y relu de 24b es innecesario.
--      Se reemplaza por logica directa sin instanciar comparador.
--   2. Bias cargado desde BRAM (fc2_biases.mif).
--   3. Pipeline flush de 2 ciclos correcto (igual que capa_oculta).
--   4. Se elimina la instancia de comparador de 24b (desperdicio
--      de LUTs) y se usa condicion directa en el proceso.
--   5. Señal mac_a/mac_b alimentadas correctamente con latencia
--      de BRAM M9K.
--
-- Salida:
--   class_out : indice 0..9 de la clase con mayor activacion
--   valid_out : '1' cuando class_out es valido
--   done      : '1' un ciclo al finalizar
-- ============================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity salida_clasificacion is
    generic (
        N_IN  : integer := 64;   -- entradas desde capa_oculta
        N_OUT : integer := 10;   -- clases MNIST
        FRAC  : integer := 7     -- fraccion Q1.7
    );
    port (
        clk       : in  std_logic;
        reset     : in  std_logic;
        en        : in  std_logic;
        data_in   : in  signed(7 downto 0);
        valid_in  : in  std_logic;
        class_out : out std_logic_vector(3 downto 0);
        valid_out : out std_logic;
        done      : out std_logic
    );
end entity;

architecture rtl of salida_clasificacion is

    component ram_sp
        generic (ADDR_W : integer; DATA_W : integer; MIF_FILE : string);
        port (clk  : in  std_logic; wr   : in  std_logic;
              addr : in  std_logic_vector(ADDR_W-1 downto 0);
              din  : in  std_logic_vector(DATA_W-1 downto 0);
              dout : out std_logic_vector(DATA_W-1 downto 0));
    end component;

    component mult_add
        port (clk, reset, en, clr : in  std_logic;
              a, b                : in  signed(7 downto 0);
              acc                 : out signed(23 downto 0));
    end component;

    -- ── BRAMs ────────────────────────────────────────────────
    -- Activaciones FC1: 64 x 8b (6 bits)
    signal act_wr   : std_logic := '0';
    signal act_addr : std_logic_vector(5 downto 0) := (others => '0');
    signal act_din  : std_logic_vector(7 downto 0) := (others => '0');
    signal act_dout : std_logic_vector(7 downto 0);

    -- Pesos FC2: 64*10 = 640 x 8b (10 bits)
    signal w_addr   : std_logic_vector(9 downto 0) := (others => '0');
    signal w_dout   : std_logic_vector(7 downto 0);

    -- Biases FC2: 10 x 8b (4 bits)
    signal b_addr   : std_logic_vector(3 downto 0) := (others => '0');
    signal b_dout   : std_logic_vector(7 downto 0);

    -- ── MAC ──────────────────────────────────────────────────
    signal mac_en    : std_logic := '0';
    signal mac_en_d  : std_logic := '0';  -- retardo 1 ciclo para BRAM
    signal mac_clr   : std_logic := '0';
    signal mac_acc   : signed(23 downto 0);

    -- ── Contadores ───────────────────────────────────────────
    signal cnt_in     : unsigned(5 downto 0) := (others => '0');  -- 0..63
    signal cnt_neur   : unsigned(3 downto 0) := (others => '0');  -- 0..9
    signal cnt_weight : unsigned(5 downto 0) := (others => '0');  -- 0..63

    -- Dirección peso: neurona * N_IN + indice_entrada (10 bits)
    signal w_base : unsigned(9 downto 0);

    -- ── Argmax ───────────────────────────────────────────────
    -- Inicializar a minimo signed 24b para que primer comparacion siempre gane
    constant MIN_SIGNED_24 : signed(23 downto 0) := (23 => '1', others => '0');
    signal max_val : signed(23 downto 0) := MIN_SIGNED_24;
    signal max_idx : unsigned(3 downto 0) := (others => '0');

    -- Acumulacion con bias
    signal biased_acc : signed(23 downto 0);

    -- ── Salidas ──────────────────────────────────────────────
    signal r_class : std_logic_vector(3 downto 0) := (others => '0');
    signal r_valid : std_logic := '0';
    signal r_done  : std_logic := '0';

    -- ── FSM ──────────────────────────────────────────────────
    type t_state is (S_LOAD, S_CALC, S_FLUSH, S_BIAS, S_ARGMAX, S_OUT, S_DONE);
    signal state     : t_state := S_LOAD;
    signal flush_cnt : unsigned(1 downto 0) := (others => '0');

begin

    -- ── Instancias ───────────────────────────────────────────
    U_ACT : ram_sp
        generic map (ADDR_W => 6, DATA_W => 8, MIF_FILE => "")
        port map (clk => clk, wr => act_wr, addr => act_addr,
                  din => act_din, dout => act_dout);

    U_W2 : ram_sp
        generic map (ADDR_W => 10, DATA_W => 8, MIF_FILE => "fc2_weights.mif")
        port map (clk => clk, wr => '0', addr => w_addr,
                  din => (others => '0'), dout => w_dout);

    U_B2 : ram_sp
        generic map (ADDR_W => 4, DATA_W => 8, MIF_FILE => "fc2_biases.mif")
        port map (clk => clk, wr => '0', addr => b_addr,
                  din => (others => '0'), dout => b_dout);

    U_MAC : mult_add
        port map (clk => clk, reset => reset, en => mac_en_d,
                  clr => mac_clr, a => signed(act_dout),
                  b => signed(w_dout), acc => mac_acc);

    -- ── Cableado combinacional ───────────────────────────────
    -- cnt_neur (4b) * N_IN (6b) -> 10b via resize post-mult.
    -- VHDL: unsigned(A)*unsigned(B) produce A+B bits; truncar explícitamente.
    w_base    <= resize(cnt_neur * to_unsigned(N_IN, 6), 10)
                 + resize(cnt_weight, 10);
    w_addr    <= std_logic_vector(w_base);
    biased_acc <= mac_acc + resize(signed(b_dout), 24);

    -- Retardo mac_en para compensar latencia BRAM
    process(clk)
    begin
        if rising_edge(clk) then
            mac_en_d <= mac_en;
        end if;
    end process;

    -- ── FSM principal ─────────────────────────────────────────
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                state      <= S_LOAD;
                cnt_in     <= (others => '0');
                cnt_neur   <= (others => '0');
                cnt_weight <= (others => '0');
                act_wr     <= '0';
                mac_en     <= '0';
                mac_clr    <= '0';
                r_valid    <= '0';
                r_done     <= '0';
                max_val    <= MIN_SIGNED_24;
                max_idx    <= (others => '0');
                flush_cnt  <= (others => '0');
            else
                mac_clr <= '0';
                r_valid <= '0';
                r_done  <= '0';
                act_wr  <= '0';

                case state is

                    -- S_LOAD: guardar activaciones FC1 ────────────
                    when S_LOAD =>
                        if en = '1' and valid_in = '1' then
                            act_wr   <= '1';
                            act_addr <= std_logic_vector(cnt_in);
                            act_din  <= std_logic_vector(data_in);
                            if cnt_in = N_IN-1 then
                                cnt_in     <= (others => '0');
                                cnt_weight <= (others => '0');
                                mac_clr    <= '1';
                                -- Reiniciar argmax
                                max_val    <= MIN_SIGNED_24;
                                max_idx    <= (others => '0');
                                state      <= S_CALC;
                            else
                                cnt_in <= cnt_in + 1;
                            end if;
                        end if;

                    -- S_CALC: acumular N_IN productos ─────────────
                    when S_CALC =>
                        act_addr <= std_logic_vector(cnt_weight);
                        mac_en   <= '1';
                        if cnt_weight = N_IN-1 then
                            mac_en     <= '0';
                            cnt_weight <= (others => '0');
                            flush_cnt  <= (others => '0');
                            state      <= S_FLUSH;
                        else
                            cnt_weight <= cnt_weight + 1;
                        end if;

                    -- S_FLUSH: vaciar pipeline MAC (2 ciclos) ─────
                    when S_FLUSH =>
                        flush_cnt <= flush_cnt + 1;
                        if flush_cnt = 2 then
                            b_addr <= std_logic_vector(cnt_neur);
                            state  <= S_BIAS;
                        end if;

                    -- S_BIAS: latencia BRAM para bias ─────────────
                    when S_BIAS =>
                        state <= S_ARGMAX;

                    -- S_ARGMAX: actualizar maximo ──────────────────
                    when S_ARGMAX =>
                        -- Comparacion directa (sin instanciar comparador extra)
                        if biased_acc > max_val then
                            max_val <= biased_acc;
                            max_idx <= cnt_neur;
                        end if;
                        mac_clr <= '1';

                        if cnt_neur = N_OUT-1 then
                            cnt_neur <= (others => '0');
                            state    <= S_OUT;
                        else
                            cnt_neur <= cnt_neur + 1;
                            state    <= S_CALC;
                        end if;

                    -- S_OUT: emitir clase ganadora ─────────────────
                    when S_OUT =>
                        r_class <= std_logic_vector(max_idx);
                        r_valid <= '1';
                        r_done  <= '1';
                        state   <= S_DONE;

                    -- S_DONE: esperar reset de habilitacion ────────
                    when S_DONE =>
                        r_done  <= '0';
                        r_valid <= '0';
                        if en = '0' then
                            state <= S_LOAD;
                        end if;

                    when others => state <= S_LOAD;
                end case;
            end if;
        end if;
    end process;

    class_out <= r_class;
    valid_out <= r_valid;
    done      <= r_done;

end architecture;
