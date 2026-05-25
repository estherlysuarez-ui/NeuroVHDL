-- ============================================================
-- Componente: conv_controller.vhd
-- Descripcion:
--   Unidad de control para la capa convolucional CNN.
--
-- Controla:
--   - Inicio de convolucion
--   - Secuencia MAC 3x3 (9 ciclos)
--   - Clear acumuladores
--   - Seleccion de filtros salida
--   - valid_out
--   - done
--
-- Arquitectura:
--
--   WAIT_WINDOW
--        ↓
--   CLR_ACC
--        ↓
--   MAC_RUN (0..8)
--        ↓
--   PIPE_FLUSH
--        ↓
--   OUTPUT_RUN (0..7)
--        ↓
--   WAIT_WINDOW
--
-- FPGA:
--   Cyclone IV
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity conv_controller is
    generic (
        N_FILT : integer := 8
    );
    port (

        -- ====================================================
        -- CLOCK / CONTROL
        -- ====================================================

        clk   : in std_logic;
        reset : in std_logic;
        en    : in std_logic;

        -- ====================================================
        -- INPUT STATUS
        -- ====================================================

        window_valid : in std_logic;

        image_done   : in std_logic;

        -- ====================================================
        -- CONTROL DSP ARRAY
        -- ====================================================

        mac_en  : out std_logic;

        mac_clr : out std_logic;

        -- ====================================================
        -- KERNEL INDEX
        -- ====================================================

        mac_idx : out std_logic_vector(3 downto 0);

        -- ====================================================
        -- FILTRO OUTPUT
        -- ====================================================

        filt_sel : out std_logic_vector(2 downto 0);

        out_valid : out std_logic;

        -- ====================================================
        -- DONE
        -- ====================================================

        done : out std_logic

    );
end entity;

architecture rtl of conv_controller is

    -- ========================================================
    -- FSM STATES
    -- ========================================================

    type t_state is (
        S_WAIT_WINDOW,
        S_CLR_ACC,
        S_MAC_RUN,
        S_PIPE_FLUSH,
        S_OUTPUT_RUN
    );

    signal state : t_state := S_WAIT_WINDOW;

    -- ========================================================
    -- CONTADORES
    -- ========================================================

    signal mac_cnt :
        unsigned(3 downto 0) := (others => '0');

    signal filt_cnt :
        unsigned(2 downto 0) := (others => '0');

    signal flush_cnt :
        unsigned(1 downto 0) := (others => '0');

begin

    -- ========================================================
    -- FSM PRINCIPAL
    -- ========================================================

    process(clk)

    begin

        if rising_edge(clk) then

            if reset = '1' then

                state <= S_WAIT_WINDOW;

                mac_cnt <= (others => '0');

                filt_cnt <= (others => '0');

                flush_cnt <= (others => '0');

            else

                case state is

                    -- ========================================
                    -- ESPERA VENTANA VALIDA
                    -- ========================================

                    when S_WAIT_WINDOW =>

                        mac_cnt <= (others => '0');

                        filt_cnt <= (others => '0');

                        flush_cnt <= (others => '0');

                        if en = '1'
                           and window_valid = '1' then

                            state <= S_CLR_ACC;

                        end if;

                    -- ========================================
                    -- LIMPIAR ACUMULADORES
                    -- ========================================

                    when S_CLR_ACC =>

                        state <= S_MAC_RUN;

                    -- ========================================
                    -- MAC 3x3
                    -- ========================================

                    when S_MAC_RUN =>

                        if mac_cnt = 8 then

                            mac_cnt <= (others => '0');

                            state <= S_PIPE_FLUSH;

                        else

                            mac_cnt <= mac_cnt + 1;

                        end if;

                    -- ========================================
                    -- FLUSH PIPELINE DSP
                    -- ========================================

                    when S_PIPE_FLUSH =>

                        if flush_cnt = 1 then

                            flush_cnt <= (others => '0');

                            state <= S_OUTPUT_RUN;

                        else

                            flush_cnt <= flush_cnt + 1;

                        end if;

                    -- ========================================
                    -- SACAR 8 FILTROS
                    -- ========================================

                    when S_OUTPUT_RUN =>

                        if filt_cnt = N_FILT-1 then

                            filt_cnt <= (others => '0');

                            state <= S_WAIT_WINDOW;

                        else

                            filt_cnt <= filt_cnt + 1;

                        end if;

                end case;

            end if;

        end if;

    end process;

    -- ========================================================
    -- OUTPUT LOGIC
    -- ========================================================

    mac_en <= '1'
        when state = S_MAC_RUN
        else '0';

    mac_clr <= '1'
        when state = S_CLR_ACC
        else '0';

    out_valid <= '1'
        when state = S_OUTPUT_RUN
        else '0';

    mac_idx <= std_logic_vector(mac_cnt);

    filt_sel <= std_logic_vector(filt_cnt);

    done <= '1'
        when image_done = '1'
        else '0';

end architecture;