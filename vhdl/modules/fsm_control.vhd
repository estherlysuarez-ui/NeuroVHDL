-- ============================================================
-- Modulo: fsm_control.vhd
-- Descripcion: Maquina de estados ONE-HOT que secuencia los
--              cinco bloques del pipeline CNN MNIST:
--
--    IDLE -> ENTRADA -> CONV -> POOL -> FC1 -> OUT -> DONE -> IDLE
--
--  Codificacion ONE-HOT (8 estados):
--    S_IDLE    : "00000001"
--    S_ENTRADA : "00000010"
--    S_CONV    : "00000100"
--    S_POOL    : "00001000"
--    S_FC1     : "00010000"
--    S_OUT     : "00100000"
--    S_DONE    : "01000000"
--    S_ERR     : "10000000"
--
--  NOTA: en_conv y en_entrada van activos al mismo tiempo porque
--  el modulo entrada alimenta pixel a pixel al modulo conv_relu.
--  Al completarse la imagen (done_entrada), la conv puede seguir
--  procesando los ultimos pixeles en su pipeline interno.
-- ============================================================
library ieee;
use ieee.std_logic_1164.all;

entity fsm_control is
    port (
        clk         : in  std_logic;
        reset       : in  std_logic;
        start       : in  std_logic;
        done_entrada: in  std_logic;
        done_conv   : in  std_logic;
        done_pool   : in  std_logic;
        done_fc     : in  std_logic;
        done_out    : in  std_logic;
        en_entrada  : out std_logic;
        en_conv     : out std_logic;
        en_pool     : out std_logic;
        en_fc       : out std_logic;
        en_out      : out std_logic;
        state_dbg   : out std_logic_vector(7 downto 0)
    );
end entity;

architecture rtl of fsm_control is

    constant S_IDLE    : std_logic_vector(7 downto 0) := "00000001";
    constant S_ENTRADA : std_logic_vector(7 downto 0) := "00000010";
    constant S_CONV    : std_logic_vector(7 downto 0) := "00000100";
    constant S_POOL    : std_logic_vector(7 downto 0) := "00001000";
    constant S_FC1     : std_logic_vector(7 downto 0) := "00010000";
    constant S_OUT     : std_logic_vector(7 downto 0) := "00100000";
    constant S_DONE    : std_logic_vector(7 downto 0) := "01000000";
    constant S_ERR     : std_logic_vector(7 downto 0) := "10000000";

    signal state : std_logic_vector(7 downto 0) := S_IDLE;

begin

    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                state <= S_IDLE;
            else
                case state is
                    when S_IDLE =>
                        if start = '1' then state <= S_ENTRADA; end if;

                    -- Entrada y Conv activos simultaneamente:
                    -- entrada sirve pixeles a conv en tiempo real
                    when S_ENTRADA =>
                        if done_entrada = '1' then state <= S_CONV; end if;

                    -- Conv sigue procesando pixeles en su pipeline
                    when S_CONV =>
                        if done_conv = '1' then state <= S_POOL; end if;

                    when S_POOL =>
                        if done_pool = '1' then state <= S_FC1; end if;

                    when S_FC1 =>
                        if done_fc = '1' then state <= S_OUT; end if;

                    when S_OUT =>
                        if done_out = '1' then state <= S_DONE; end if;

                    when S_DONE =>
                        state <= S_IDLE;

                    when S_ERR =>
                        state <= S_ERR;

                    when others =>
                        state <= S_ERR;
                end case;
            end if;
        end if;
    end process;

    -- Decodificacion Moore directa desde bits del estado ONE-HOT
    en_entrada <= state(1);  -- S_ENTRADA activa entrada
    en_conv    <= state(1) or state(2);  -- conv activa en ENTRADA y CONV
    en_pool    <= state(3);
    en_fc      <= state(4);
    en_out     <= state(5);
    state_dbg  <= state;

end architecture;
