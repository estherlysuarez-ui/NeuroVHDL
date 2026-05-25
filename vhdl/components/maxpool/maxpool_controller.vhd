-- ============================================================
-- Componente: maxpool_controller.vhd
-- Descripcion:
--   Controlador secuencial para maxpool 2x2 streaming.
--
-- Funcion:
--
--   FILA PAR:
--      - escribir pixel en line buffer
--      - guardar pixel izquierdo cuando col par
--
--   FILA IMPAR:
--      - col par:
--            guardar bot-left
--            capturar top-left
--
--      - col impar:
--            ventana 2x2 completa
--            emitir pool_valid
--
-- Arquitectura:
--
--   maxpool_controller
--   ├── control line buffer
--   ├── control registros
--   └── control salida pooling
--
-- FPGA:
--   Cyclone IV
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity maxpool_controller is
    port (

        -- ====================================================
        -- CLOCK / CONTROL
        -- ====================================================

        clk   : in std_logic;
        reset : in std_logic;

        en    : in std_logic;

        valid_in : in std_logic;

        -- ====================================================
        -- FLAGS COUNTERS
        -- ====================================================

        even_row : in std_logic;
        even_col : in std_logic;

        -- ====================================================
        -- CONTROL OUTPUTS
        -- ====================================================

        lb_wr : out std_logic;

        reg_left_cur_en : out std_logic;
        reg_left_top_en : out std_logic;

        pool_valid : out std_logic

    );
end entity;

architecture rtl of maxpool_controller is

    signal r_lb_wr : std_logic := '0';

    signal r_left_cur_en : std_logic := '0';
    signal r_left_top_en : std_logic := '0';

    signal r_pool_valid : std_logic := '0';

begin

    process(clk)
    begin
        if rising_edge(clk) then

            if reset = '1' then

                r_lb_wr        <= '0';

                r_left_cur_en  <= '0';
                r_left_top_en  <= '0';

                r_pool_valid   <= '0';

            else

                -- ====================================================
                -- DEFAULTS
                -- ====================================================

                r_lb_wr        <= '0';

                r_left_cur_en  <= '0';
                r_left_top_en  <= '0';

                r_pool_valid   <= '0';

                -- ====================================================
                -- MAXPOOL CONTROL
                -- ====================================================

                if en = '1' and valid_in = '1' then

                    -- =================================================
                    -- FILA PAR
                    -- =================================================

                    if even_row = '1' then

                        -- escribir line buffer
                        r_lb_wr <= '1';

                        -- guardar pixel izquierdo
                        if even_col = '1' then
                            r_left_cur_en <= '1';
                        end if;

                    -- =================================================
                    -- FILA IMPAR
                    -- =================================================

                    else

                        -- =============================================
                        -- COLUMNA PAR
                        -- =============================================

                        if even_col = '1' then

                            -- guardar bot-left
                            r_left_cur_en <= '1';

                            -- capturar top-left
                            r_left_top_en <= '1';

                        -- =============================================
                        -- COLUMNA IMPAR
                        -- =============================================

                        else

                            -- ventana 2x2 completa
                            r_pool_valid <= '1';

                        end if;

                    end if;

                end if;

            end if;
        end if;
    end process;

    -- ========================================================
    -- OUTPUTS
    -- ========================================================

    lb_wr <= r_lb_wr;

    reg_left_cur_en <= r_left_cur_en;

    reg_left_top_en <= r_left_top_en;

    pool_valid <= r_pool_valid;

end architecture;