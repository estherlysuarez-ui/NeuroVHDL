-- ============================================================
-- Modulo: entrada.vhd
-- Descripcion:
--   Modulo de entrada CNN completamente estructural.
--
-- Arquitectura:
--
--   entrada
--   ├── U_COUNTER     : contador pixeles
--   ├── U_REG_ADDR    : pipeline direccion BRAM
--   ├── U_IMG_RAM     : BRAM imagen
--   └── valid pipeline
--
-- Funcion:
--
--   1. Permite cargar imagen externamente
--   2. Lee secuencialmente 784 pixeles
--   3. Entrega stream a conv_relu
--
-- FPGA:
--   Cyclone IV EP4CE22
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity entrada is
    port (

        -- ====================================================
        -- CLOCK / CONTROL
        -- ====================================================

        clk   : in std_logic;
        reset : in std_logic;
        en    : in std_logic;

        -- ====================================================
        -- CARGA EXTERNA IMAGEN
        -- ====================================================

        img_wr   : in std_logic;

        img_addr : in std_logic_vector(9 downto 0);

        img_din  : in std_logic_vector(7 downto 0);

        -- ====================================================
        -- OUTPUT STREAM CNN
        -- ====================================================

        pixel_out : out signed(7 downto 0);

        valid_out : out std_logic;

        done      : out std_logic

    );
end entity;

architecture structural of entrada is

    -- ========================================================
    -- COMPONENTES
    -- ========================================================

    component contador
        generic (
            N   : integer := 8;
            MAX : integer := 255
        );
        port (
            clk   : in  std_logic;
            reset : in  std_logic;
            en    : in  std_logic;

            cnt   : out std_logic_vector(N-1 downto 0);

            done  : out std_logic
        );
    end component;

    component registro
        generic (
            N : integer := 8
        );
        port (
            clk   : in  std_logic;
            reset : in  std_logic;
            en    : in  std_logic;

            d     : in  std_logic_vector(N-1 downto 0);

            q     : out std_logic_vector(N-1 downto 0)
        );
    end component;

    component ram_sp
        generic (
            ADDR_W   : integer := 10;
            DATA_W   : integer := 8;
            MIF_FILE : string  := ""
        );
        port (
            clk  : in  std_logic;
            wr   : in  std_logic;

            addr : in  std_logic_vector(ADDR_W-1 downto 0);

            din  : in  std_logic_vector(DATA_W-1 downto 0);

            dout : out std_logic_vector(DATA_W-1 downto 0)
        );
    end component;

    -- ========================================================
    -- CONTADOR PIXELES
    -- ========================================================

    signal cnt_pix : std_logic_vector(9 downto 0);

    signal cnt_done : std_logic;

    -- ========================================================
    -- REGISTRO DIRECCION
    -- ========================================================

    signal addr_reg : std_logic_vector(9 downto 0);

    -- ========================================================
    -- BRAM
    -- ========================================================

    signal img_addr_mux : std_logic_vector(9 downto 0);

    signal img_dout : std_logic_vector(7 downto 0);

    -- ========================================================
    -- PIPELINE VALID
    -- ========================================================

    signal valid_pipe : std_logic := '0';

begin

    -- ========================================================
    -- CONTADOR PIXELES
    -- ========================================================

    U_COUNTER : contador
        generic map (
            N   => 10,
            MAX => 783
        )
        port map (

            clk   => clk,
            reset => reset,
            en    => en,

            cnt   => cnt_pix,

            done  => cnt_done
        );

    -- ========================================================
    -- REGISTRO DIRECCION BRAM
    -- ========================================================

    U_REG_ADDR : registro
        generic map (
            N => 10
        )
        port map (

            clk   => clk,
            reset => reset,
            en    => en,

            d => cnt_pix,

            q => addr_reg
        );

    -- ========================================================
    -- MUX DIRECCION BRAM
    -- ========================================================

    img_addr_mux <=
        img_addr when img_wr = '1'
        else addr_reg;

    -- ========================================================
    -- BRAM IMAGEN
    -- ========================================================

    U_IMG_RAM : ram_sp
        generic map (
            ADDR_W => 10,
            DATA_W => 8,
            MIF_FILE => ""
        )
        port map (

            clk  => clk,

            wr   => img_wr,

            addr => img_addr_mux,

            din  => img_din,

            dout => img_dout
        );

    -- ========================================================
    -- PIPELINE VALID
    -- ========================================================

    process(clk)
    begin

        if rising_edge(clk) then

            if reset = '1' then

                valid_pipe <= '0';

            else

                -- Compensa latencia de BRAM M9K
                valid_pipe <= en;

            end if;

        end if;

    end process;

    -- ========================================================
    -- OUTPUTS
    -- ========================================================

    pixel_out <= signed(img_dout);

    valid_out <= valid_pipe;

    done <= cnt_done;

end architecture;