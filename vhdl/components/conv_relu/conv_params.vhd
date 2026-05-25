-- ============================================================
-- Modulo: conv_params.vhd
-- Descripcion:
--   Banco de parametros de la capa convolucional.
--
-- Contiene:
--   - 8 ROMs de kernels 3x3
--   - 1 ROM de bias
--
-- Archivos:
--   kernel0.mif ... kernel7.mif
--   conv1_bias.mif
--
-- Compatible con:
--   ram_sp.vhd
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;

entity conv_params is
    port (

        -- direccion peso kernel (0..8)
        kernel_addr : in std_logic_vector(3 downto 0);

        -- direccion bias (0..7)
        bias_addr   : in std_logic_vector(2 downto 0);

        clk         : in std_logic;

        -- pesos kernels
        k0_out      : out std_logic_vector(7 downto 0);
        k1_out      : out std_logic_vector(7 downto 0);
        k2_out      : out std_logic_vector(7 downto 0);
        k3_out      : out std_logic_vector(7 downto 0);
        k4_out      : out std_logic_vector(7 downto 0);
        k5_out      : out std_logic_vector(7 downto 0);
        k6_out      : out std_logic_vector(7 downto 0);
        k7_out      : out std_logic_vector(7 downto 0);

        -- bias
        bias_out    : out std_logic_vector(7 downto 0)
    );
end entity;

architecture structural of conv_params is

    -- ========================================================
    -- COMPONENTE RAM
    -- ========================================================

    component ram_sp
        generic (
            ADDR_W  : integer;
            DATA_W  : integer;
            MIF_FILE : string
        );
        port (
            clk  : in  std_logic;
            wr   : in  std_logic;
            addr : in  std_logic_vector(ADDR_W-1 downto 0);
            din  : in  std_logic_vector(DATA_W-1 downto 0);
            dout : out std_logic_vector(DATA_W-1 downto 0)
        );
    end component;

begin

    -- ========================================================
    -- KERNEL 0
    -- ========================================================

    U_KERNEL0_ROM : ram_sp
        generic map (
            ADDR_W  => 4,
            DATA_W  => 8,
            MIF_FILE => "kernel0.mif"
        )
        port map (
            clk  => clk,
            wr   => '0',
            addr => kernel_addr,
            din  => (others => '0'),
            dout => k0_out
        );

    -- ========================================================
    -- KERNEL 1
    -- ========================================================

    U_KERNEL1_ROM : ram_sp
        generic map (
            ADDR_W  => 4,
            DATA_W  => 8,
            MIF_FILE => "kernel1.mif"
        )
        port map (
            clk  => clk,
            wr   => '0',
            addr => kernel_addr,
            din  => (others => '0'),
            dout => k1_out
        );

    -- ========================================================
    -- KERNEL 2
    -- ========================================================

    U_KERNEL2_ROM : ram_sp
        generic map (
            ADDR_W  => 4,
            DATA_W  => 8,
            MIF_FILE => "kernel2.mif"
        )
        port map (
            clk  => clk,
            wr   => '0',
            addr => kernel_addr,
            din  => (others => '0'),
            dout => k2_out
        );

    -- ========================================================
    -- KERNEL 3
    -- ========================================================

    U_KERNEL3_ROM : ram_sp
        generic map (
            ADDR_W  => 4,
            DATA_W  => 8,
            MIF_FILE => "kernel3.mif"
        )
        port map (
            clk  => clk,
            wr   => '0',
            addr => kernel_addr,
            din  => (others => '0'),
            dout => k3_out
        );

    -- ========================================================
    -- KERNEL 4
    -- ========================================================

    U_KERNEL4_ROM : ram_sp
        generic map (
            ADDR_W  => 4,
            DATA_W  => 8,
            MIF_FILE => "kernel4.mif"
        )
        port map (
            clk  => clk,
            wr   => '0',
            addr => kernel_addr,
            din  => (others => '0'),
            dout => k4_out
        );

    -- ========================================================
    -- KERNEL 5
    -- ========================================================

    U_KERNEL5_ROM : ram_sp
        generic map (
            ADDR_W  => 4,
            DATA_W  => 8,
            MIF_FILE => "kernel5.mif"
        )
        port map (
            clk  => clk,
            wr   => '0',
            addr => kernel_addr,
            din  => (others => '0'),
            dout => k5_out
        );

    -- ========================================================
    -- KERNEL 6
    -- ========================================================

    U_KERNEL6_ROM : ram_sp
        generic map (
            ADDR_W  => 4,
            DATA_W  => 8,
            MIF_FILE => "kernel6.mif"
        )
        port map (
            clk  => clk,
            wr   => '0',
            addr => kernel_addr,
            din  => (others => '0'),
            dout => k6_out
        );

    -- ========================================================
    -- KERNEL 7
    -- ========================================================

    U_KERNEL7_ROM : ram_sp
        generic map (
            ADDR_W  => 4,
            DATA_W  => 8,
            MIF_FILE => "kernel7.mif"
        )
        port map (
            clk  => clk,
            wr   => '0',
            addr => kernel_addr,
            din  => (others => '0'),
            dout => k7_out
        );

    -- ========================================================
    -- BIAS ROM
    -- ========================================================

    U_BIAS_ROM : ram_sp
        generic map (
            ADDR_W  => 3,
            DATA_W  => 8,
            MIF_FILE => "conv1_bias.mif"
        )
        port map (
            clk  => clk,
            wr   => '0',
            addr => bias_addr,
            din  => (others => '0'),
            dout => bias_out
        );

end architecture;
