-- ============================================================
-- Modulo: main.vhd  (top-level estructural)
-- Descripcion:
--   Implementacion completa CNN para MNIST en FPGA Cyclone IV.
--
-- Arquitectura:
--
--   Imagen 28x28
--        ↓
--      entrada
--   (RAM + contador + pipeline)
--        ↓
--     conv_relu
--   (Conv3x3 + ReLU)
--        ↓
--      maxpool
--        ↓
--      FC1
--        ↓
--      FC2 + Argmax
--
-- FPGA:
--   Cyclone IV EP4CE22
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity main is
    port (

        -- ====================================================
        -- CLOCK / CONTROL
        -- ====================================================

        clk   : in std_logic;
        reset : in std_logic;
        start : in std_logic;

        -- ====================================================
        -- CARGA EXTERNA IMAGEN
        -- ====================================================

        img_wr   : in std_logic;

        img_addr : in std_logic_vector(9 downto 0);

        img_din  : in std_logic_vector(7 downto 0);

        -- ====================================================
        -- RESULTADO
        -- ====================================================

        class_out : out std_logic_vector(3 downto 0);

        valid_out : out std_logic;

        done : out std_logic;

        -- ====================================================
        -- DEBUG FSM
        -- ====================================================

        state_dbg : out std_logic_vector(7 downto 0)

    );
end entity;

architecture structural of main is

    -- ========================================================
    -- COMPONENTES
    -- ========================================================

    component fsm_control
        port (

            clk   : in std_logic;
            reset : in std_logic;

            start : in std_logic;

            done_entrada : in std_logic;
            done_conv    : in std_logic;
            done_pool    : in std_logic;
            done_fc      : in std_logic;
            done_out     : in std_logic;

            en_entrada : out std_logic;
            en_conv    : out std_logic;
            en_pool    : out std_logic;
            en_fc      : out std_logic;
            en_out     : out std_logic;

            state_dbg : out std_logic_vector(7 downto 0)

        );
    end component;

    component entrada
        port (

            clk   : in std_logic;
            reset : in std_logic;

            en    : in std_logic;

            -- ====================================================
            -- ESCRITURA EXTERNA BRAM
            -- ====================================================

            img_wr   : in std_logic;

            img_addr : in std_logic_vector(9 downto 0);

            img_din  : in std_logic_vector(7 downto 0);

            -- ====================================================
            -- STREAM HACIA CNN
            -- ====================================================

            pixel_out : out signed(7 downto 0);

            valid_out : out std_logic;

            done : out std_logic

        );
    end component;

    component conv_relu
        generic (
            IMG_W  : integer := 28;
            N_FILT : integer := 8;
            FRAC   : integer := 7
        );
        port (

            clk   : in std_logic;
            reset : in std_logic;

            en : in std_logic;

            pixel_in : in signed(7 downto 0);

            valid_in : in std_logic;

            conv_out : out signed(7 downto 0);

            filt_idx : out std_logic_vector(2 downto 0);

            valid_out : out std_logic;

            done : out std_logic

        );
    end component;

    component maxpool
        generic (
            IMG_W  : integer := 28;
            N_FILT : integer := 8
        );
        port (

            clk   : in std_logic;
            reset : in std_logic;

            en : in std_logic;

            data_in : in signed(7 downto 0);

            filt_in : in std_logic_vector(2 downto 0);

            valid_in : in std_logic;

            pool_out : out signed(7 downto 0);

            filt_out : out std_logic_vector(2 downto 0);

            valid_out : out std_logic;

            done : out std_logic

        );
    end component;

    component capa_oculta
        generic (
            N_IN  : integer := 1352;
            N_OUT : integer := 64;
            FRAC  : integer := 7
        );
        port (

            clk   : in std_logic;
            reset : in std_logic;

            en : in std_logic;

            data_in : in signed(7 downto 0);

            valid_in : in std_logic;

            fc_out : out signed(7 downto 0);

            valid_out : out std_logic;

            done : out std_logic

        );
    end component;

    component salida_clasificacion
        generic (
            N_IN  : integer := 64;
            N_OUT : integer := 10;
            FRAC  : integer := 7
        );
        port (

            clk   : in std_logic;
            reset : in std_logic;

            en : in std_logic;

            data_in : in signed(7 downto 0);

            valid_in : in std_logic;

            class_out : out std_logic_vector(3 downto 0);

            valid_out : out std_logic;

            done : out std_logic

        );
    end component;

    -- ========================================================
    -- FSM -> BLOQUES
    -- ========================================================

    signal en_entrada : std_logic;
    signal en_conv    : std_logic;
    signal en_pool    : std_logic;
    signal en_fc      : std_logic;
    signal en_out     : std_logic;

    -- ========================================================
    -- DONE BLOQUES
    -- ========================================================

    signal done_entrada : std_logic;
    signal done_conv    : std_logic;
    signal done_pool    : std_logic;
    signal done_fc      : std_logic;
    signal done_out     : std_logic;

    -- ========================================================
    -- ENTRADA -> CONV
    -- ========================================================

    signal pixel_out   : signed(7 downto 0);

    signal pixel_valid : std_logic;

    -- ========================================================
    -- CONV -> POOL
    -- ========================================================

    signal conv_out   : signed(7 downto 0);

    signal conv_fidx  : std_logic_vector(2 downto 0);

    signal conv_valid : std_logic;

    -- ========================================================
    -- POOL -> FC1
    -- ========================================================

    signal pool_out   : signed(7 downto 0);

    signal pool_fidx  : std_logic_vector(2 downto 0);

    signal pool_valid : std_logic;

    -- ========================================================
    -- FC1 -> FC2
    -- ========================================================

    signal fc1_out   : signed(7 downto 0);

    signal fc1_valid : std_logic;

begin

    -- ========================================================
    -- FSM CONTROL
    -- ========================================================

    U_FSM : fsm_control
        port map (

            clk   => clk,
            reset => reset,

            start => start,

            done_entrada => done_entrada,
            done_conv    => done_conv,
            done_pool    => done_pool,
            done_fc      => done_fc,
            done_out     => done_out,

            en_entrada => en_entrada,
            en_conv    => en_conv,
            en_pool    => en_pool,
            en_fc      => en_fc,
            en_out     => en_out,

            state_dbg => state_dbg
        );

    -- ========================================================
    -- ENTRADA + RAM + PIPELINE
    -- ========================================================

    U_ENTRADA : entrada
        port map (

            clk   => clk,
            reset => reset,

            en => en_entrada,

            -- carga imagen externa

            img_wr   => img_wr,

            img_addr => img_addr,

            img_din  => img_din,

            -- salida stream CNN

            pixel_out => pixel_out,

            valid_out => pixel_valid,

            done => done_entrada
        );

    -- ========================================================
    -- CONVOLUTION + RELU
    -- ========================================================

    U_CONV : conv_relu
        generic map (
            IMG_W  => 28,
            N_FILT => 8,
            FRAC   => 7
        )
        port map (

            clk   => clk,
            reset => reset,

            en => en_conv,

            pixel_in => pixel_out,

            valid_in => pixel_valid,

            conv_out => conv_out,

            filt_idx => conv_fidx,

            valid_out => conv_valid,

            done => done_conv
        );

    -- ========================================================
    -- MAXPOOL
    -- ========================================================

    U_POOL : maxpool
        generic map (
            IMG_W  => 28,
            N_FILT => 8
        )
        port map (

            clk   => clk,
            reset => reset,

            en => en_pool,

            data_in => conv_out,

            filt_in => conv_fidx,

            valid_in => conv_valid,

            pool_out => pool_out,

            filt_out => pool_fidx,

            valid_out => pool_valid,

            done => done_pool
        );

    -- ========================================================
    -- FC1
    -- ========================================================

    U_FC1 : capa_oculta
        generic map (
            N_IN  => 1352,
            N_OUT => 64,
            FRAC  => 7
        )
        port map (

            clk   => clk,
            reset => reset,

            en => en_fc,

            data_in => pool_out,

            valid_in => pool_valid,

            fc_out => fc1_out,

            valid_out => fc1_valid,

            done => done_fc
        );

    -- ========================================================
    -- FC2 + ARGMAX
    -- ========================================================

    U_FC2 : salida_clasificacion
        generic map (
            N_IN  => 64,
            N_OUT => 10,
            FRAC  => 7
        )
        port map (

            clk   => clk,
            reset => reset,

            en => en_out,

            data_in => fc1_out,

            valid_in => fc1_valid,

            class_out => class_out,

            valid_out => valid_out,

            done => done_out
        );

    -- ========================================================
    -- DONE GLOBAL
    -- ========================================================

    done <= done_out;

end architecture;