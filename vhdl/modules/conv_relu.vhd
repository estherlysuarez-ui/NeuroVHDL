-- ============================================================
-- Modulo: conv_relu.vhd
-- Descripcion:
--   Capa convolucional 3x3 + ReLU completamente estructural.
--
-- Arquitectura:
--
--   conv_relu
--   ├── U_LINE_BUFFER   : line_buffer_3x3
--   ├── U_CONTROLLER    : conv_controller
--   ├── U_PARAMS        : conv_params
--   ├── U_MAC_ARRAY     : mac_accum_array
--   └── U_RELU          : relu_block
--
-- NOTA:
--   El selector de ventana 3x3 ya fue integrado dentro de
--   mac_accum_array, por lo que conv_relu queda totalmente
--   modular y limpio.
--
-- FPGA:
--   Cyclone IV EP4CE22
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity conv_relu is
    generic (
        IMG_W  : integer := 28;
        N_FILT : integer := 8;
        FRAC   : integer := 7
    );
    port (

        -- ====================================================
        -- CLOCK / CONTROL
        -- ====================================================

        clk   : in std_logic;
        reset : in std_logic;
        en    : in std_logic;

        -- ====================================================
        -- INPUT PIXEL STREAM
        -- ====================================================

        pixel_in : in signed(7 downto 0);

        valid_in : in std_logic;

        -- ====================================================
        -- OUTPUT FEATURE MAP
        -- ====================================================

        conv_out : out signed(7 downto 0);

        filt_idx : out std_logic_vector(2 downto 0);

        valid_out : out std_logic;

        done : out std_logic

    );
end entity;

architecture structural of conv_relu is

    -- ========================================================
    -- COMPONENTES
    -- ========================================================

    component line_buffer_3x3
        generic (
            IMG_W : integer := 28
        );
        port (
            clk       : in  std_logic;
            reset     : in  std_logic;
            en        : in  std_logic;

            pixel_in  : in  signed(7 downto 0);
            valid_in  : in  std_logic;

            win0      : out signed(7 downto 0);
            win1      : out signed(7 downto 0);
            win2      : out signed(7 downto 0);

            win3      : out signed(7 downto 0);
            win4      : out signed(7 downto 0);
            win5      : out signed(7 downto 0);

            win6      : out signed(7 downto 0);
            win7      : out signed(7 downto 0);
            win8      : out signed(7 downto 0);

            win_valid : out std_logic
        );
    end component;

    component conv_params
        port (

            kernel_addr : in std_logic_vector(3 downto 0);

            bias_addr   : in std_logic_vector(2 downto 0);

            clk         : in std_logic;

            k0_out      : out std_logic_vector(7 downto 0);
            k1_out      : out std_logic_vector(7 downto 0);
            k2_out      : out std_logic_vector(7 downto 0);
            k3_out      : out std_logic_vector(7 downto 0);
            k4_out      : out std_logic_vector(7 downto 0);
            k5_out      : out std_logic_vector(7 downto 0);
            k6_out      : out std_logic_vector(7 downto 0);
            k7_out      : out std_logic_vector(7 downto 0);

            bias_out    : out std_logic_vector(7 downto 0)
        );
    end component;

	component mac_accum_array
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
	end component;

    component relu_block
        generic (
            FRAC : integer := 7
        );
        port (

            acc0 : in signed(23 downto 0);
            acc1 : in signed(23 downto 0);
            acc2 : in signed(23 downto 0);
            acc3 : in signed(23 downto 0);
            acc4 : in signed(23 downto 0);
            acc5 : in signed(23 downto 0);
            acc6 : in signed(23 downto 0);
            acc7 : in signed(23 downto 0);

            bias0 : in signed(7 downto 0);
            bias1 : in signed(7 downto 0);
            bias2 : in signed(7 downto 0);
            bias3 : in signed(7 downto 0);
            bias4 : in signed(7 downto 0);
            bias5 : in signed(7 downto 0);
            bias6 : in signed(7 downto 0);
            bias7 : in signed(7 downto 0);

            filt_sel : in std_logic_vector(2 downto 0);

            relu_out : out signed(7 downto 0)

        );
    end component;

    component conv_controller
        generic (
            N_FILT : integer := 8
        );
        port (

            clk   : in std_logic;
            reset : in std_logic;
            en    : in std_logic;

            window_valid : in std_logic;

            image_done   : in std_logic;

            mac_en  : out std_logic;

            mac_clr : out std_logic;

            mac_idx : out std_logic_vector(3 downto 0);

            filt_sel : out std_logic_vector(2 downto 0);

            out_valid : out std_logic;

            done : out std_logic

        );
    end component;

    -- ========================================================
    -- LINE BUFFER
    -- ========================================================

    signal win0 : signed(7 downto 0);
    signal win1 : signed(7 downto 0);
    signal win2 : signed(7 downto 0);

    signal win3 : signed(7 downto 0);
    signal win4 : signed(7 downto 0);
    signal win5 : signed(7 downto 0);

    signal win6 : signed(7 downto 0);
    signal win7 : signed(7 downto 0);
    signal win8 : signed(7 downto 0);

    signal win_valid : std_logic;

    -- ========================================================
    -- CONTROLLER
    -- ========================================================

    signal mac_en  : std_logic;
    signal mac_clr : std_logic;

    signal mac_idx : std_logic_vector(3 downto 0);

    signal filt_sel : std_logic_vector(2 downto 0);

    signal out_valid_i : std_logic;

    -- ========================================================
    -- KERNELS
    -- ========================================================

    signal k0 : std_logic_vector(7 downto 0);
    signal k1 : std_logic_vector(7 downto 0);
    signal k2 : std_logic_vector(7 downto 0);
    signal k3 : std_logic_vector(7 downto 0);
    signal k4 : std_logic_vector(7 downto 0);
    signal k5 : std_logic_vector(7 downto 0);
    signal k6 : std_logic_vector(7 downto 0);
    signal k7 : std_logic_vector(7 downto 0);

    signal bias_dummy : std_logic_vector(7 downto 0);

    -- ========================================================
    -- ACCUMULATORS
    -- ========================================================

    signal acc0 : signed(23 downto 0);
    signal acc1 : signed(23 downto 0);
    signal acc2 : signed(23 downto 0);
    signal acc3 : signed(23 downto 0);
    signal acc4 : signed(23 downto 0);
    signal acc5 : signed(23 downto 0);
    signal acc6 : signed(23 downto 0);
    signal acc7 : signed(23 downto 0);

begin

    -- ========================================================
    -- LINE BUFFER + WINDOW
    -- ========================================================

    U_LINE_BUFFER : line_buffer_3x3
        generic map (
            IMG_W => IMG_W
        )
        port map (

            clk => clk,
            reset => reset,
            en => en,

            pixel_in => pixel_in,
            valid_in => valid_in,

            win0 => win0,
            win1 => win1,
            win2 => win2,

            win3 => win3,
            win4 => win4,
            win5 => win5,

            win6 => win6,
            win7 => win7,
            win8 => win8,

            win_valid => win_valid
        );

    -- ========================================================
    -- CONTROLADOR
    -- ========================================================

    U_CONTROLLER : conv_controller
        generic map (
            N_FILT => N_FILT
        )
        port map (

            clk => clk,
            reset => reset,
            en => en,

            window_valid => win_valid,

            image_done => '0',

            mac_en => mac_en,
            mac_clr => mac_clr,

            mac_idx => mac_idx,

            filt_sel => filt_sel,

            out_valid => out_valid_i,

            done => done
        );

    -- ========================================================
    -- PARAMETROS CNN
    -- ========================================================

    U_PARAMS : conv_params
        port map (

            kernel_addr => mac_idx,

            bias_addr => filt_sel,

            clk => clk,

            k0_out => k0,
            k1_out => k1,
            k2_out => k2,
            k3_out => k3,
            k4_out => k4,
            k5_out => k5,
            k6_out => k6,
            k7_out => k7,

            bias_out => bias_dummy
        );

    -- ========================================================
    -- MAC ARRAY + SELECTOR 3x3
    -- ========================================================

    U_MAC_ARRAY : mac_accum_array
    generic map (
        N_FILT => N_FILT
    )
    port map (

        clk => clk,
        reset => reset,

        en => mac_en,
        clr => mac_clr,

        mac_idx => mac_idx,

        win0 => win0,
        win1 => win1,
        win2 => win2,

        win3 => win3,
        win4 => win4,
        win5 => win5,

        win6 => win6,
        win7 => win7,
        win8 => win8,

        kernel0 => signed(k0),
        kernel1 => signed(k1),
        kernel2 => signed(k2),
        kernel3 => signed(k3),
        kernel4 => signed(k4),
        kernel5 => signed(k5),
        kernel6 => signed(k6),
        kernel7 => signed(k7),

        acc0 => acc0,
        acc1 => acc1,
        acc2 => acc2,
        acc3 => acc3,
        acc4 => acc4,
        acc5 => acc5,
        acc6 => acc6,
        acc7 => acc7
    );
    -- ========================================================
    -- RELU + BIAS
    -- ========================================================

    U_RELU : relu_block
        generic map (
            FRAC => FRAC
        )
        port map (

            acc0 => acc0,
            acc1 => acc1,
            acc2 => acc2,
            acc3 => acc3,
            acc4 => acc4,
            acc5 => acc5,
            acc6 => acc6,
            acc7 => acc7,

            bias0 => to_signed(0,8),
            bias1 => to_signed(0,8),
            bias2 => to_signed(0,8),
            bias3 => to_signed(0,8),
            bias4 => to_signed(0,8),
            bias5 => to_signed(0,8),
            bias6 => to_signed(0,8),
            bias7 => to_signed(0,8),

            filt_sel => filt_sel,

            relu_out => conv_out
        );

    -- ========================================================
    -- OUTPUTS
    -- ========================================================

    filt_idx <= filt_sel;

    valid_out <= out_valid_i;

end architecture;