-- ============================================================
-- Componente: maxpool_counters.vhd
-- Descripcion:
--   Contadores de posicion para maxpool 2x2.
--
-- Arquitectura:
--
--   maxpool_counters
--   ├── U_COL_COUNTER
--   ├── U_ROW_COUNTER
--   └── U_OUT_COUNTER
--
-- Funciones:
--   - Control fila/columna imagen
--   - Flags par/impar
--   - Señal done pooling
--
-- FPGA:
--   Cyclone IV
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity maxpool_counters is
    generic (
        IMG_W  : integer := 28;
        N_FILT : integer := 8
    );
    port (

        -- ====================================================
        -- CLOCK / CONTROL
        -- ====================================================

        clk      : in std_logic;
        reset    : in std_logic;
        en       : in std_logic;

        valid_in : in std_logic;

        filt_in  : in std_logic_vector(2 downto 0);

        pool_valid : in std_logic;

        -- ====================================================
        -- OUTPUTS
        -- ====================================================

        row_out : out std_logic_vector(4 downto 0);
        col_out : out std_logic_vector(4 downto 0);

        even_row : out std_logic;
        even_col : out std_logic;

        last_row : out std_logic;
        last_col : out std_logic;

        done : out std_logic

    );
end entity;

architecture structural of maxpool_counters is

    -- ========================================================
    -- COMPONENTE CONTADOR
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

    -- ========================================================
    -- SEÑALES
    -- ========================================================

    signal col_cnt : std_logic_vector(4 downto 0);
    signal row_cnt : std_logic_vector(4 downto 0);

    signal col_done : std_logic;
    signal row_done : std_logic;

    signal out_done : std_logic;

    signal filt_last : std_logic;

    signal col_en : std_logic;
    signal row_en : std_logic;
    signal out_en : std_logic;

begin

    -- ========================================================
    -- ULTIMO FILTRO
    -- ========================================================

    filt_last <= '1'
        when unsigned(filt_in) = N_FILT-1
        else '0';

    -- ========================================================
    -- ENABLES
    -- ========================================================

    col_en <= valid_in and en and filt_last;

    row_en <= valid_in and en and filt_last and col_done;

    out_en <= pool_valid;

    -- ========================================================
    -- CONTADOR COLUMNA
    -- ========================================================

    U_COL_COUNTER : contador
        generic map (
            N   => 5,
            MAX => IMG_W-1
        )
        port map (

            clk   => clk,
            reset => reset,
            en    => col_en,

            cnt   => col_cnt,

            done  => col_done
        );

    -- ========================================================
    -- CONTADOR FILA
    -- ========================================================

    U_ROW_COUNTER : contador
        generic map (
            N   => 5,
            MAX => IMG_W-1
        )
        port map (

            clk   => clk,
            reset => reset,
            en    => row_en,

            cnt   => row_cnt,

            done  => row_done
        );

    -- ========================================================
    -- CONTADOR OUTPUTS
    -- ========================================================

    U_OUT_COUNTER : contador
        generic map (
            N   => 11,
            MAX => (IMG_W/2)*(IMG_W/2)*N_FILT - 1
        )
        port map (

            clk   => clk,
            reset => reset,
            en    => out_en,

            cnt   => open,

            done  => out_done
        );

    -- ========================================================
    -- FLAGS
    -- ========================================================

    even_row <= not row_cnt(0);

    even_col <= not col_cnt(0);

    last_row <= row_done;

    last_col <= col_done;

    -- ========================================================
    -- OUTPUTS
    -- ========================================================

    row_out <= row_cnt;

    col_out <= col_cnt;

    done <= out_done;

end architecture;