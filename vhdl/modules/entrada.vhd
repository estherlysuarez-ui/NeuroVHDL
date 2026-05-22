-- ============================================================
-- Modulo: entrada.vhd
-- Descripcion: Lee pixeles de la BRAM (imagen 28x28 = 784 px)
--              Genera direccion con contador fila + columna.
--              Salida: pixel_out en Q0.8 (0..255 -> signed 8b).
--              valid_out indica pixel valido al siguiente bloque.
-- ============================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity entrada is
    port (
        clk       : in  std_logic;
        reset     : in  std_logic;
        en        : in  std_logic;        -- habilitado por FSM (en_conv)
        -- interfaz BRAM externa (imagen cargada antes)
        addr      : out std_logic_vector(9 downto 0);  -- 0..783
        rd_en     : out std_logic;
        pixel_in  : in  std_logic_vector(7 downto 0);  -- dato de BRAM
        -- salida al bloque convolucional
        pixel_out : out signed(7 downto 0);            -- Q0.8 unsigned
        valid_out : out std_logic;
        done      : out std_logic         -- imagen completa
    );
end entity;

architecture rtl of entrada is

    -- Contadores fila y columna (0..27)
    signal cnt_col      : std_logic_vector(4 downto 0);  -- 0..27
    signal cnt_fil      : std_logic_vector(4 downto 0);
    signal done_col     : std_logic;
    signal done_fil     : std_logic;
    signal en_fil       : std_logic;

    -- Registro de salida
    signal r_pixel      : signed(7 downto 0) := (others => '0');
    signal r_valid      : std_logic := '0';
    signal r_addr       : unsigned(9 downto 0) := (others => '0');

    -- Componentes internos
    component contador
        generic (N : integer; MAX : integer);
        port (clk,reset,en : in std_logic;
              cnt : out std_logic_vector(N-1 downto 0);
              done : out std_logic);
    end component;

begin

    -- Contador columna: 0..27, cada ciclo activo
    U_COL : contador
        generic map (N => 5, MAX => 27)
        port map (clk=>clk, reset=>reset, en=>en,
                  cnt=>cnt_col, done=>done_col);

    -- Contador fila: avanza cuando columna llega a 27
    en_fil <= done_col;
    U_FIL : contador
        generic map (N => 5, MAX => 27)
        port map (clk=>clk, reset=>reset, en=>en_fil,
                  cnt=>cnt_fil, done=>done_fil);

    -- Calculo de direccion lineal: addr = fila*28 + columna
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                r_addr  <= (others => '0');
                r_valid <= '0';
                r_pixel <= (others => '0');
            elsif en = '1' then
                -- direccion = fila*28 + col
                r_addr  <= unsigned(cnt_fil) * 28 + unsigned(cnt_col);
                r_pixel <= signed(pixel_in);  -- sin signo -> signed (0..255)
                r_valid <= '1';
            else
                r_valid <= '0';
            end if;
        end if;
    end process;

    -- Salidas
    addr      <= std_logic_vector(r_addr);
    rd_en     <= en;
    pixel_out <= r_pixel;
    valid_out <= r_valid;
    done      <= done_fil and done_col;

end architecture;
