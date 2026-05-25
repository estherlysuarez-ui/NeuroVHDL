-- ============================================================
-- Componente: mac_accumulator_array.vhd
-- Descripcion:
--   Banco de 8 MACs paralelos para la capa convolucional.
--
-- Arquitectura:
--   - Selector interno ventana 3x3
--   - 8 instancias mult_add
--   - 8 DSPs paralelos
--   - Acumulacion pipeline
--
-- Flujo:
--
--      ventana 3x3
--            ↓
--      selector interno
--            ↓
--        8 MAC DSP
--            ↓
--      acumuladores
--
-- FPGA:
--   Cyclone IV
--
-- Formato:
--   Q1.7 signed
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity mac_accum_array is
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
        clr   : in std_logic;

        -- ====================================================
        -- VENTANA 3x3
        -- ====================================================

        win0 : in signed(7 downto 0);
        win1 : in signed(7 downto 0);
        win2 : in signed(7 downto 0);

        win3 : in signed(7 downto 0);
        win4 : in signed(7 downto 0);
        win5 : in signed(7 downto 0);

        win6 : in signed(7 downto 0);
        win7 : in signed(7 downto 0);
        win8 : in signed(7 downto 0);

        -- ====================================================
        -- INDICE KERNEL
        -- ====================================================

        mac_idx : in std_logic_vector(3 downto 0);

        -- ====================================================
        -- PESOS KERNELS
        -- ====================================================

        kernel0 : in signed(7 downto 0);
        kernel1 : in signed(7 downto 0);
        kernel2 : in signed(7 downto 0);
        kernel3 : in signed(7 downto 0);
        kernel4 : in signed(7 downto 0);
        kernel5 : in signed(7 downto 0);
        kernel6 : in signed(7 downto 0);
        kernel7 : in signed(7 downto 0);

        -- ====================================================
        -- ACUMULADORES
        -- ====================================================

        acc0 : out signed(23 downto 0);
        acc1 : out signed(23 downto 0);
        acc2 : out signed(23 downto 0);
        acc3 : out signed(23 downto 0);
        acc4 : out signed(23 downto 0);
        acc5 : out signed(23 downto 0);
        acc6 : out signed(23 downto 0);
        acc7 : out signed(23 downto 0)

    );
end entity;

architecture structural of mac_accum_array is

    -- ========================================================
    -- COMPONENTE MAC
    -- ========================================================

    component mult_add
        port (
            clk   : in  std_logic;
            reset : in  std_logic;
            en    : in  std_logic;
            clr   : in  std_logic;

            a     : in  signed(7 downto 0);
            b     : in  signed(7 downto 0);

            acc   : out signed(23 downto 0)
        );
    end component;

    -- ========================================================
    -- PIXEL SELECCIONADO
    -- ========================================================

    signal pixel_sel : signed(7 downto 0);

begin

    -- ========================================================
    -- SELECTOR VENTANA 3x3
    -- ========================================================

    with mac_idx select
        pixel_sel <=

            win0 when "0000",
            win1 when "0001",
            win2 when "0010",

            win3 when "0011",
            win4 when "0100",
            win5 when "0101",

            win6 when "0110",
            win7 when "0111",
            win8 when "1000",

            (others => '0') when others;

    -- ========================================================
    -- MAC FILTRO 0
    -- ========================================================

    U_MAC0 : mult_add
        port map (
            clk   => clk,
            reset => reset,
            en    => en,
            clr   => clr,

            a     => pixel_sel,
            b     => kernel0,

            acc   => acc0
        );

    -- ========================================================
    -- MAC FILTRO 1
    -- ========================================================

    U_MAC1 : mult_add
        port map (
            clk   => clk,
            reset => reset,
            en    => en,
            clr   => clr,

            a     => pixel_sel,
            b     => kernel1,

            acc   => acc1
        );

    -- ========================================================
    -- MAC FILTRO 2
    -- ========================================================

    U_MAC2 : mult_add
        port map (
            clk   => clk,
            reset => reset,
            en    => en,
            clr   => clr,

            a     => pixel_sel,
            b     => kernel2,

            acc   => acc2
        );

    -- ========================================================
    -- MAC FILTRO 3
    -- ========================================================

    U_MAC3 : mult_add
        port map (
            clk   => clk,
            reset => reset,
            en    => en,
            clr   => clr,

            a     => pixel_sel,
            b     => kernel3,

            acc   => acc3
        );

    -- ========================================================
    -- MAC FILTRO 4
    -- ========================================================

    U_MAC4 : mult_add
        port map (
            clk   => clk,
            reset => reset,
            en    => en,
            clr   => clr,

            a     => pixel_sel,
            b     => kernel4,

            acc   => acc4
        );

    -- ========================================================
    -- MAC FILTRO 5
    -- ========================================================

    U_MAC5 : mult_add
        port map (
            clk   => clk,
            reset => reset,
            en    => en,
            clr   => clr,

            a     => pixel_sel,
            b     => kernel5,

            acc   => acc5
        );

    -- ========================================================
    -- MAC FILTRO 6
    -- ========================================================

    U_MAC6 : mult_add
        port map (
            clk   => clk,
            reset => reset,
            en    => en,
            clr   => clr,

            a     => pixel_sel,
            b     => kernel6,

            acc   => acc6
        );

    -- ========================================================
    -- MAC FILTRO 7
    -- ========================================================

    U_MAC7 : mult_add
        port map (
            clk   => clk,
            reset => reset,
            en    => en,
            clr   => clr,

            a     => pixel_sel,
            b     => kernel7,

            acc   => acc7
        );

end architecture;