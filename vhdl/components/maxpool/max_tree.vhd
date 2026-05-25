-- ============================================================
-- Componente: max_tree.vhd
-- Descripcion:
--   Arbol de comparadores MAX para ventana 2x2.
--
-- Funcion:
--
--        TL ───┐
--              MAX0 ──┐
--        TR ───┘      │
--                     MAX2 ─── MAX_FINAL
--        BL ───┐      │
--              MAX1 ──┘
--        BR ───┘
--
-- Arquitectura:
--   - 3 comparadores estructurales
--   - totalmente combinacional
--   - sin DSPs
--   - mapeo eficiente a carry chains Cyclone IV
--
-- FPGA:
--   Cyclone IV
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity max_tree is
    port (

        -- ====================================================
        -- ENTRADAS VENTANA 2x2
        -- ====================================================

        top_left  : in signed(7 downto 0);
        top_right : in signed(7 downto 0);

        bot_left  : in signed(7 downto 0);
        bot_right : in signed(7 downto 0);

        -- ====================================================
        -- SALIDA MAXIMA
        -- ====================================================

        max_out : out signed(7 downto 0)

    );
end entity;

architecture structural of max_tree is

    -- ========================================================
    -- COMPONENTE COMPARADOR
    -- ========================================================

    component comparadorv2
        generic (
            N : integer := 8
        );
        port (

            a : in signed(N-1 downto 0);
            b : in signed(N-1 downto 0);

            mayor : out std_logic;
            igual : out std_logic;

            max_out : out signed(N-1 downto 0);

            relu : out signed(N-1 downto 0)

        );
    end component;

    -- ========================================================
    -- SEÑALES INTERNAS
    -- ========================================================

    signal max0 : signed(7 downto 0);
    signal max1 : signed(7 downto 0);

begin

    -- ========================================================
    -- MAX(TOP_LEFT, TOP_RIGHT)
    -- ========================================================

    U_MAX0 : comparadorv2
        generic map (
            N => 8
        )
        port map (

            a => top_left,
            b => top_right,

            mayor => open,
            igual => open,

            max_out => max0,

            relu => open
        );

    -- ========================================================
    -- MAX(BOT_LEFT, BOT_RIGHT)
    -- ========================================================

    U_MAX1 : comparadorv2
        generic map (
            N => 8
        )
        port map (

            a => bot_left,
            b => bot_right,

            mayor => open,
            igual => open,

            max_out => max1,

            relu => open
        );

    -- ========================================================
    -- MAX FINAL
    -- ========================================================

    U_MAX2 : comparadorv2
        generic map (
            N => 8
        )
        port map (

            a => max0,
            b => max1,

            mayor => open,
            igual => open,

            max_out => max_out,

            relu => open
        );

end architecture;