-- ============================================================
-- Modulo: capa_oculta.vhd
-- Descripcion: Capa completamente conectada FC1: 1352->64
--              con activacion ReLU en Q1.7.
--
-- OPTIMIZACIONES vs. version original:
--   1. BIAS cargado desde BRAM (fc1_biases.mif) en vez de
--      constante de ceros hardcodeada.
--   2. Pipeline de 2 etapas del MAC (consistente con mult_add
--      optimizado): gating correcto para no perder muestras.
--   3. Calculo w_base en 17 bits sin riesgo de truncamiento:
--      se usa unsigned de ancho adecuado antes de la suma.
--   4. Latencia de BRAM M9K (1 ciclo) correctamente manejada
--      con retardo de 1 ciclo en mac_en despues de act_addr.
--   5. Estado S_FLUSH para vaciar el pipeline de 2 ciclos del MAC.
--
-- Interfaz:
--   data_in/valid_in  : activaciones aplanadas del maxpool
--   fc_out/valid_out  : salidas ReLU Q1.7 de las 64 neuronas
--   done              : '1' cuando las 64 neuronas estan listas
-- ============================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity capa_oculta is
    generic (
        N_IN  : integer := 1352;  -- 13*13*8 activaciones entrada
        N_OUT : integer := 64;    -- neuronas en la capa oculta
        FRAC  : integer := 7      -- fraccion Q1.7
    );
    port (
        clk       : in  std_logic;
        reset     : in  std_logic;
        en        : in  std_logic;
        data_in   : in  signed(7 downto 0);
        valid_in  : in  std_logic;
        fc_out    : out signed(7 downto 0);
        valid_out : out std_logic;
        done      : out std_logic
    );
end entity;

architecture rtl of capa_oculta is

    -- ── Declaraciones de componentes ─────────────────────────
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
    -- Activaciones: 1352 x 8b (11 bits de direccion)
    signal act_wr   : std_logic := '0';
    signal act_addr : std_logic_vector(10 downto 0) := (others => '0');
    signal act_din  : std_logic_vector(7 downto 0)  := (others => '0');
    signal act_dout : std_logic_vector(7 downto 0);

    -- Pesos FC1: 1352*64 = 86528 x 8b (17 bits de direccion)
    signal w_addr   : std_logic_vector(16 downto 0) := (others => '0');
    signal w_dout   : std_logic_vector(7 downto 0);

    -- Biases FC1: 64 x 8b (6 bits de direccion)
    signal b_addr   : std_logic_vector(5 downto 0)  := (others => '0');
    signal b_dout   : std_logic_vector(7 downto 0);

    -- ── MAC ──────────────────────────────────────────────────
    signal mac_en  : std_logic := '0';
    signal mac_clr : std_logic := '0';
    signal mac_acc : signed(23 downto 0);

    -- Retardo 1 ciclo para compensar latencia BRAM M9K
    signal mac_en_d : std_logic := '0';

    -- ── Contadores ───────────────────────────────────────────
    signal cnt_in     : unsigned(10 downto 0) := (others => '0');  -- 0..1351
    signal cnt_neur   : unsigned(5 downto 0)  := (others => '0');  -- 0..63
    signal cnt_weight : unsigned(10 downto 0) := (others => '0');  -- 0..1351

    -- Dirección de peso: neurona * N_IN + indice_entrada (17 bits)
    signal w_base : unsigned(16 downto 0);

    -- ── Salidas ──────────────────────────────────────────────
    signal r_out   : signed(7 downto 0) := (others => '0');
    signal r_valid : std_logic := '0';
    signal r_done  : std_logic := '0';

    -- ── FSM ──────────────────────────────────────────────────
    type t_state is (S_LOAD, S_CALC, S_FLUSH, S_BIAS, S_OUT, S_DONE);
    signal state : t_state := S_LOAD;

    -- Contador de flush (2 ciclos de pipeline)
    signal flush_cnt : unsigned(1 downto 0) := (others => '0');

    -- Resultado con bias antes de ReLU
    signal biased_acc : signed(23 downto 0);

begin

    -- ── Instancias ───────────────────────────────────────────
    U_ACT_RAM : ram_sp
        generic map (ADDR_W => 11, DATA_W => 8, MIF_FILE => "")
        port map (clk => clk, wr => act_wr, addr => act_addr,
                  din => act_din, dout => act_dout);

    U_W_RAM : ram_sp
        generic map (ADDR_W => 17, DATA_W => 8, MIF_FILE => "fc1_weights.mif")
        port map (clk => clk, wr => '0', addr => w_addr,
                  din => (others => '0'), dout => w_dout);

    U_B_RAM : ram_sp
        generic map (ADDR_W => 6, DATA_W => 8, MIF_FILE => "fc1_biases.mif")
        port map (clk => clk, wr => '0', addr => b_addr,
                  din => (others => '0'), dout => b_dout);

    U_MAC : mult_add
        port map (clk => clk, reset => reset, en => mac_en_d,
                  clr => mac_clr, a => signed(act_dout),
                  b => signed(w_dout), acc => mac_acc);

    -- ── Calculo combinacional de dirección de peso ────────────
    -- cnt_neur (6b) * N_IN constante -> producto 17b via resize post-mult.
    -- VHDL: unsigned(A)*unsigned(B) produce A+B bits; hay que truncar.
    w_base <= resize(cnt_neur * to_unsigned(N_IN, 11), 17)
              + resize(cnt_weight, 17);
    w_addr <= std_logic_vector(w_base);

    -- ── Resultado con bias: acc + bias (extendido a 24b) ─────
    biased_acc <= mac_acc + resize(signed(b_dout), 24);

    -- ── Retardo mac_en para compensar latencia BRAM ───────────
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
                flush_cnt  <= (others => '0');
            else
                mac_clr <= '0';
                r_valid <= '0';
                r_done  <= '0';
                act_wr  <= '0';

                case state is

                    -- S_LOAD: almacenar activaciones de maxpool ─
                    when S_LOAD =>
                        if en = '1' and valid_in = '1' then
                            act_wr   <= '1';
                            act_addr <= std_logic_vector(cnt_in);
                            act_din  <= std_logic_vector(data_in);
                            if cnt_in = N_IN-1 then
                                cnt_in     <= (others => '0');
                                cnt_weight <= (others => '0');
                                mac_clr    <= '1';
                                state      <= S_CALC;
                            else
                                cnt_in <= cnt_in + 1;
                            end if;
                        end if;

                    -- S_CALC: acumular N_IN productos para neurona cnt_neur
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

                    -- S_FLUSH: vaciar pipeline de 2 ciclos del MAC ─
                    when S_FLUSH =>
                        flush_cnt <= flush_cnt + 1;
                        if flush_cnt = 2 then
                            -- Leer bias para esta neurona
                            b_addr <= std_logic_vector(cnt_neur);
                            state  <= S_BIAS;
                        end if;

                    -- S_BIAS: 1 ciclo latencia BRAM para bias ─────
                    when S_BIAS =>
                        state <= S_OUT;

                    -- S_OUT: aplicar bias + ReLU y emitir resultado ─
                    when S_OUT =>
                        -- ReLU: si bit de signo = 1 -> negativo -> 0
                        if biased_acc(23) = '0' then
                            -- Truncar a Q1.7: tomar bits [FRAC+7:FRAC]
                            r_out <= biased_acc(FRAC+7 downto FRAC);
                        else
                            r_out <= (others => '0');
                        end if;
                        r_valid <= '1';
                        mac_clr <= '1';

                        if cnt_neur = N_OUT-1 then
                            cnt_neur <= (others => '0');
                            r_done   <= '1';
                            state    <= S_DONE;
                        else
                            cnt_neur <= cnt_neur + 1;
                            state    <= S_CALC;
                        end if;

                    -- S_DONE: esperar nueva habilitacion ──────────
                    when S_DONE =>
                        if en = '0' then
                            state <= S_LOAD;
                        end if;

                    when others => state <= S_LOAD;
                end case;
            end if;
        end if;
    end process;

    fc_out    <= r_out;
    valid_out <= r_valid;
    done      <= r_done;

end architecture;
