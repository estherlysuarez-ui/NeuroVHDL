-- ============================================================
-- Modulo: fsm_control.vhd
-- Descripcion: Maquina de estados ONE-HOT que secuencia los
--              cinco bloques del pipeline CNN MNIST:
--
--    IDLE -> CONV -> POOL -> FC1 -> OUT -> DONE -> IDLE
--
--  Codificacion ONE-HOT (7 estados):
--    S_IDLE : "0000001"
--    S_CONV : "0000010"
--    S_POOL : "0000100"
--    S_FC1  : "0001000"
--    S_OUT  : "0010000"
--    S_DONE : "0100000"
--    S_ERR  : "1000000"  (estado de error)
--
--  Senales de control generadas:
--    en_conv  -> habilita bloque conv_relu
--    en_pool  -> habilita bloque maxpool
--    en_fc    -> habilita bloque capa_oculta
--    en_out   -> habilita bloque salida_clasificacion
-- ============================================================
library ieee;
use ieee.std_logic_1164.all;

entity fsm_control is
    port (
        clk      : in  std_logic;
        reset    : in  std_logic;
        start    : in  std_logic;   -- pulso de inicio (1 ciclo)
        -- flags de terminacion de cada bloque
        done_conv : in  std_logic;
        done_pool : in  std_logic;
        done_fc   : in  std_logic;
        done_out  : in  std_logic;
        -- habilitaciones a cada bloque
        en_conv  : out std_logic;
        en_pool  : out std_logic;
        en_fc    : out std_logic;
        en_out   : out std_logic;
        -- estado observable (para debug / testbench)
        state_dbg: out std_logic_vector(6 downto 0)
    );
end entity;

architecture rtl of fsm_control is

    -- ── Codificacion ONE-HOT ─────────────────────────────────
    constant S_IDLE : std_logic_vector(6 downto 0) := "0000001";
    constant S_CONV : std_logic_vector(6 downto 0) := "0000010";
    constant S_POOL : std_logic_vector(6 downto 0) := "0000100";
    constant S_FC1  : std_logic_vector(6 downto 0) := "0001000";
    constant S_OUT  : std_logic_vector(6 downto 0) := "0010000";
    constant S_DONE : std_logic_vector(6 downto 0) := "0100000";
    constant S_ERR  : std_logic_vector(6 downto 0) := "1000000";

    signal state : std_logic_vector(6 downto 0) := S_IDLE;

begin

    -- ── Registro de estado (sincrono) ────────────────────────
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                state <= S_IDLE;
            else
                case state is
                    -- Esperar orden de inicio ─────────────────
                    when S_IDLE =>
                        if start = '1' then
                            state <= S_CONV;
                        end if;

                    -- Convolucional activa ─────────────────────
                    when S_CONV =>
                        if done_conv = '1' then
                            state <= S_POOL;
                        end if;

                    -- MaxPooling activo ────────────────────────
                    when S_POOL =>
                        if done_pool = '1' then
                            state <= S_FC1;
                        end if;

                    -- Capa oculta FC1 activa ───────────────────
                    when S_FC1 =>
                        if done_fc = '1' then
                            state <= S_OUT;
                        end if;

                    -- Salida/clasificacion activa ──────────────
                    when S_OUT =>
                        if done_out = '1' then
                            state <= S_DONE;
                        end if;

                    -- Resultado listo, volver a IDLE ──────────
                    when S_DONE =>
                        state <= S_IDLE;

                    -- Estado de error: reset requerido ────────
                    when S_ERR =>
                        state <= S_ERR;

                    -- One-hot invalido -> error ────────────────
                    when others =>
                        state <= S_ERR;
                end case;
            end if;
        end if;
    end process;

    -- ── Salidas Moore (decodificacion directa) ───────────────
    en_conv   <= state(1);  -- bit 1 = S_CONV
    en_pool   <= state(2);  -- bit 2 = S_POOL
    en_fc     <= state(3);  -- bit 3 = S_FC1
    en_out    <= state(4);  -- bit 4 = S_OUT
    state_dbg <= state;

end architecture;
