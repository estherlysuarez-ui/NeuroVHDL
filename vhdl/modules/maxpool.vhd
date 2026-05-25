-- ============================================================
-- Modulo: maxpool.vhd (REFACTORIZADO)
-- Descripcion:
--   MaxPooling 2x2 completamente estructural.
--   No contiene lógica de control ni contadores internos.
--
-- Arquitectura:
--
--   maxpool
--   ├── maxpool_counters
--   ├── maxpool_controller
--   ├── line buffer (ram_sp)
--   ├── registros (left_cur, left_top)
--   └── max_tree
--
-- FPGA: Cyclone IV
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity maxpool is
    generic (
        IMG_W  : integer := 28;
        N_FILT : integer := 8
    );
    port (
        clk       : in  std_logic;
        reset     : in  std_logic;
        en        : in  std_logic;

        data_in   : in  signed(7 downto 0);
        filt_in   : in  std_logic_vector(2 downto 0);
        valid_in  : in  std_logic;

        pool_out  : out signed(7 downto 0);
        filt_out  : out std_logic_vector(2 downto 0);
        valid_out : out std_logic;
        done      : out std_logic
    );
end entity;

architecture structural of maxpool is

    -- ========================================================
    -- COMPONENTES BASE
    -- ========================================================

    component ram_sp
        generic (ADDR_W : integer; DATA_W : integer; MIF_FILE : string);
        port (
            clk  : in  std_logic;
            wr   : in  std_logic;
            addr : in  std_logic_vector(7 downto 0);
            din  : in  std_logic_vector(7 downto 0);
            dout : out std_logic_vector(7 downto 0)
        );
    end component;

    component maxpool_counters
        generic (IMG_W : integer; N_FILT : integer);
        port (
            clk        : in std_logic;
            reset      : in std_logic;
            en         : in std_logic;
            valid_in   : in std_logic;
            filt_in    : in std_logic_vector(2 downto 0);

            row_out    : out std_logic_vector(4 downto 0);
            col_out    : out std_logic_vector(4 downto 0);
            even_row   : out std_logic;
            even_col   : out std_logic;
            done       : out std_logic
        );
    end component;

    component maxpool_controller
        port (
            clk              : in std_logic;
            reset            : in std_logic;
            en               : in std_logic;
            valid_in         : in std_logic;

            even_row         : in std_logic;
            even_col         : in std_logic;

            lb_wr            : out std_logic;
            reg_left_cur_en  : out std_logic;
            reg_left_top_en  : out std_logic;
            pool_valid       : out std_logic
        );
    end component;

    component max_tree
        port (
            top_left  : in signed(7 downto 0);
            top_right : in signed(7 downto 0);
            bot_left  : in signed(7 downto 0);
            bot_right : in signed(7 downto 0);
            max_out   : out signed(7 downto 0)
        );
    end component;

    component registro
        generic (N : integer := 8);
        port (
            clk   : in std_logic;
            reset : in std_logic;
            en    : in std_logic;
            d     : in std_logic_vector(N-1 downto 0);
            q     : out std_logic_vector(N-1 downto 0)
        );
    end component;

    -- ========================================================
    -- SEÑALES INTERNAS
    -- ========================================================

    signal row_cnt, col_cnt : std_logic_vector(4 downto 0);
    signal even_row, even_col : std_logic;

    signal lb_wr : std_logic;
    signal lb_addr : std_logic_vector(7 downto 0);
    signal lb_dout : std_logic_vector(7 downto 0);

    signal left_cur_d, left_cur_q : std_logic_vector(7 downto 0);
    signal left_top_d, left_top_q : std_logic_vector(7 downto 0);

    signal reg_left_cur_en, reg_left_top_en : std_logic;

    signal top_left, top_right : signed(7 downto 0);
    signal bot_left, bot_right : signed(7 downto 0);

    signal max_val : signed(7 downto 0);

    signal pool_valid : std_logic;

begin

    -- ========================================================
    -- COUNTERS
    -- ========================================================

    U_COUNTERS : maxpool_counters
        generic map (
            IMG_W  => IMG_W,
            N_FILT => N_FILT
        )
        port map (
            clk      => clk,
            reset    => reset,
            en       => en,
            valid_in => valid_in,
            filt_in  => filt_in,

            row_out  => row_cnt,
            col_out  => col_cnt,

            even_row => even_row,
            even_col => even_col,

            done     => done
        );

    -- ========================================================
    -- CONTROLLER
    -- ========================================================

    U_CTRL : maxpool_controller
        port map (
            clk              => clk,
            reset            => reset,
            en               => en,
            valid_in         => valid_in,

            even_row         => even_row,
            even_col         => even_col,

            lb_wr            => lb_wr,
            reg_left_cur_en  => reg_left_cur_en,
            reg_left_top_en  => reg_left_top_en,
            pool_valid       => pool_valid
        );

    -- ========================================================
    -- LINE BUFFER (BRAM)
    -- ========================================================

    lb_addr <= std_logic_vector(
        resize(unsigned(filt_in), 8) * to_unsigned(IMG_W, 8)
        + resize(unsigned(col_cnt), 8)
    );

    U_LB : ram_sp
        generic map (
            ADDR_W => 8,
            DATA_W => 8,
            MIF_FILE => ""
        )
        port map (
            clk  => clk,
            wr   => lb_wr,
            addr => lb_addr,
            din  => std_logic_vector(data_in),
            dout => lb_dout
        );

    -- ========================================================
    -- REGISTROS DE VENTANA
    -- ========================================================

    -- left_cur
    U_REG_LC : registro
        port map (
            clk   => clk,
            reset => reset,
            en    => reg_left_cur_en,
            d     => std_logic_vector(data_in),
            q     => left_cur_q
        );

    -- left_top
    U_REG_LT : registro
        port map (
            clk   => clk,
            reset => reset,
            en    => reg_left_top_en,
            d     => lb_dout,
            q     => left_top_q
        );

    -- ========================================================
    -- MAX TREE (2x2 pooling)
    -- ========================================================

    top_left  <= signed(left_top_q);
    top_right <= signed(lb_dout);
    bot_left  <= signed(left_cur_q);
    bot_right <= data_in;

    U_MAX : max_tree
        port map (
            top_left  => top_left,
            top_right => top_right,
            bot_left  => bot_left,
            bot_right => bot_right,
            max_out   => max_val
        );

    -- ========================================================
    -- SALIDAS
    -- ========================================================

    pool_out  <= max_val;
    filt_out  <= filt_in;
    valid_out <= pool_valid;

end architecture;