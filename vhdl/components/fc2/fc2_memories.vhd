-- ============================================================
-- Modulo: fc2_memories.vhd
-- Descripcion: Bloque unificado de memoria para la capa FC2.
--              Agrupa activaciones FC1, pesos FC2 y biases FC2.
-- ============================================================
library ieee;
use ieee.std_logic_1164.all;

entity fc2_memories is
    port (
        clk        : in  std_logic;
        
        -- Interfaz Memoria de Activaciones de Entrada (64 x 8b)
        act_wr     : in  std_logic;
        act_addr   : in  std_logic_vector(5 downto 0);
        act_din    : in  std_logic_vector(7 downto 0);
        act_dout   : out std_logic_vector(7 downto 0);
        
        -- Interfaz Memoria de Pesos FC2 (640 x 8b)
        w_addr     : in  std_logic_vector(9 downto 0);
        w_dout     : out std_logic_vector(7 downto 0);
        
        -- Interfaz Memoria de Biases FC2 (10 x 8b)
        b_addr     : in  std_logic_vector(3 downto 0);
        b_dout     : out std_logic_vector(7 downto 0)
    );
end entity;

architecture rtl of fc2_memories is
    component ram_sp
        generic (ADDR_W : integer; DATA_W : integer; MIF_FILE : string);
        port (
            clk  : in  std_logic;
            wr   : in  std_logic;
            addr : in  std_logic_vector(ADDR_W-1 downto 0);
            din  : in  std_logic_vector(DATA_W-1 downto 0);
            dout : out std_logic_vector(DATA_W-1 downto 0)
        );
    end component;
begin

    -- RAM Activaciones de la capa anterior
    U_ACT_RAM2 : ram_sp
        generic map (ADDR_W => 6, DATA_W => 8, MIF_FILE => "")
        port map (clk => clk, wr => act_wr, addr => act_addr, din => act_din, dout => act_dout);

    -- ROM de Pesos Capa de Salida
    U_W_RAM2 : ram_sp
        generic map (ADDR_W => 10, DATA_W => 8, MIF_FILE => "fc2_weights.mif")
        port map (clk => clk, wr => '0', addr => w_addr, din => (others => '0'), dout => w_dout);

    -- ROM de Biases Capa de Salida
    U_B_RAM2 : ram_sp
        generic map (ADDR_W => 4, DATA_W => 8, MIF_FILE => "fc2_biases.mif")
        port map (clk => clk, wr => '0', addr => b_addr, din => (others => '0'), dout => b_dout);

end architecture;