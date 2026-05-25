-- ============================================================
-- Modulo: line_buffer_3x3.vhd
-- Descripcion:
--   Genera ventana deslizante 3x3 para convolucion CNN.
--
-- Arquitectura:
--   - 2 BRAM line buffers
--   - registros shift para ventana
--   - contador de columnas
--
-- Entrada:
--   pixel_in + valid_in
--
-- Salida:
--   win0..win8 (ventana 3x3)
--   win_valid
--
-- Compatible con:
--   - ram_sp.vhd
--   - contador.vhd
--   - registro.vhd
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity line_buffer_3x3 is
    generic (
        IMG_W : integer := 28
    );
    port (
        clk       : in  std_logic;
        reset     : in  std_logic;
        en        : in  std_logic;

        pixel_in  : in  signed(7 downto 0);
        valid_in  : in  std_logic;

        -- ventana 3x3
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
end entity;

architecture structural of line_buffer_3x3 is

    -- ========================================================
    -- COMPONENTES
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

    component contador
        generic (
            N   : integer;
            MAX : integer
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
        generic (N : integer := 8);
        port (
            clk   : in  std_logic;
            reset : in  std_logic;
            en    : in  std_logic;
            d     : in  std_logic_vector(N-1 downto 0);
            q     : out std_logic_vector(N-1 downto 0)
        );
    end component;

    -- ========================================================
    -- LINE BUFFERS
    -- ========================================================

    signal lb0_dout : std_logic_vector(7 downto 0);
    signal lb1_dout : std_logic_vector(7 downto 0);

    signal col_cnt  : std_logic_vector(4 downto 0);

    -- ========================================================
    -- REGISTROS VENTANA
    -- ========================================================

    signal r0_0, r0_1, r0_2 : std_logic_vector(7 downto 0);
    signal r1_0, r1_1, r1_2 : std_logic_vector(7 downto 0);
    signal r2_0, r2_1, r2_2 : std_logic_vector(7 downto 0);

    -- ========================================================
    -- CONTROL
    -- ========================================================

    signal row_cnt : unsigned(5 downto 0) := (others => '0');

begin

    -- ========================================================
    -- CONTADOR COLUMNAS
    -- ========================================================

    U_COL_CNT : contador
        generic map (
            N   => 5,
            MAX => IMG_W-1
        )
        port map (
            clk   => clk,
            reset => reset,
            en    => valid_in,
            cnt   => col_cnt,
            done  => open
        );

    -- ========================================================
    -- LINE BUFFER 0
    -- ========================================================

    U_LINE_RAM_0 : ram_sp
        generic map (
            ADDR_W  => 5,
            DATA_W  => 8,
            MIF_FILE => ""
        )
        port map (
            clk  => clk,
            wr   => valid_in,
            addr => col_cnt,
            din  => lb1_dout,
            dout => lb0_dout
        );

    -- ========================================================
    -- LINE BUFFER 1
    -- ========================================================

    U_LINE_RAM_1 : ram_sp
        generic map (
            ADDR_W  => 5,
            DATA_W  => 8,
            MIF_FILE => ""
        )
        port map (
            clk  => clk,
            wr   => valid_in,
            addr => col_cnt,
            din  => std_logic_vector(pixel_in),
            dout => lb1_dout
        );

    -- ========================================================
    -- FILA 0
    -- ========================================================

    U_R0C0 : registro
        port map (
            clk   => clk,
            reset => reset,
            en    => valid_in,
            d     => lb0_dout,
            q     => r0_0
        );

    U_R0C1 : registro
        port map (
            clk   => clk,
            reset => reset,
            en    => valid_in,
            d     => r0_0,
            q     => r0_1
        );

    U_R0C2 : registro
        port map (
            clk   => clk,
            reset => reset,
            en    => valid_in,
            d     => r0_1,
            q     => r0_2
        );

    -- ========================================================
    -- FILA 1
    -- ========================================================

    U_R1C0 : registro
        port map (
            clk   => clk,
            reset => reset,
            en    => valid_in,
            d     => lb1_dout,
            q     => r1_0
        );

    U_R1C1 : registro
        port map (
            clk   => clk,
            reset => reset,
            en    => valid_in,
            d     => r1_0,
            q     => r1_1
        );

    U_R1C2 : registro
        port map (
            clk   => clk,
            reset => reset,
            en    => valid_in,
            d     => r1_1,
            q     => r1_2
        );

    -- ========================================================
    -- FILA 2
    -- ========================================================

    U_R2C0 : registro
        port map (
            clk   => clk,
            reset => reset,
            en    => valid_in,
            d     => std_logic_vector(pixel_in),
            q     => r2_0
        );

    U_R2C1 : registro
        port map (
            clk   => clk,
            reset => reset,
            en    => valid_in,
            d     => r2_0,
            q     => r2_1
        );

    U_R2C2 : registro
        port map (
            clk   => clk,
            reset => reset,
            en    => valid_in,
            d     => r2_1,
            q     => r2_2
        );

    -- ========================================================
    -- CONTADOR FILAS
    -- ========================================================

    process(clk)
    begin
        if rising_edge(clk) then

            if reset = '1' then
                row_cnt <= (others => '0');

            elsif valid_in = '1' then

                if unsigned(col_cnt) = IMG_W-1 then
                    row_cnt <= row_cnt + 1;
                end if;

            end if;
        end if;
    end process;

    -- ========================================================
    -- VALID WINDOW
    -- ========================================================

    win_valid <= '1'
        when row_cnt >= 2
        and unsigned(col_cnt) >= 2
        else '0';

    -- ========================================================
    -- OUTPUTS
    -- ========================================================

    win0 <= signed(r0_0);
    win1 <= signed(r0_1);
    win2 <= signed(r0_2);

    win3 <= signed(r1_0);
    win4 <= signed(r1_1);
    win5 <= signed(r1_2);

    win6 <= signed(r2_0);
    win7 <= signed(r2_1);
    win8 <= signed(r2_2);

end architecture;
