-- ============================================================
-- Modulo: fc_memories.vhd
-- Descripcion: Bloque unificado de memoria para la capa oculta.
--              Agrupa activaciones, pesos y biases protegiendo
--              el paralelismo de lectura requerido por el MAC.
-- ============================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fc_memories is
    port (
        clk        : in  std_logic;
        
        -- Interfaz Memoria de Activaciones (RAM de lectura/escritura)
        act_wr     : in  std_logic;
        act_addr   : in  std_logic_vector(10 downto 0);
        act_din    : in  std_logic_vector(7 downto 0);
        act_dout   : out std_logic_vector(7 downto 0);
        
        -- Interfaz Memoria de Pesos (ROM pre-cargada)
        w_addr     : in  std_logic_vector(16 downto 0);
        w_dout     : out std_logic_vector(7 downto 0);
        
        -- Interfaz Memoria de Biases (ROM pre-cargada)
        b_addr     : in  std_logic_vector(5 downto 0);
        b_dout     : out std_logic_vector(7 downto 0)
    );
end entity;

architecture rtl of fc_memories is

    -- Componente base reutilizable
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

    -- ── Memoria de Activaciones (1352 x 8b) ──────────────────
    U_ACT_RAM : ram_sp
        generic map (ADDR_W => 11, DATA_W => 8, MIF_FILE => "")
        port map (
            clk  => clk,
            wr   => act_wr,
            addr => act_addr,
            din  => act_din,
            dout => act_dout
        );

    -- ── Memoria de Pesos (86528 x 8b) ────────────────────────
    U_W_RAM : ram_sp
        generic map (ADDR_W => 17, DATA_W => 8, MIF_FILE => "fc1_weights.mif")
        port map (
            clk  => clk,
            wr   => '0', -- Solo lectura
            addr => w_addr,
            din  => (others => '0'),
            dout => w_dout
        );

    -- ── Memoria de Biases (64 x 8b) ──────────────────────────
    U_B_RAM : ram_sp
        generic map (ADDR_W => 6, DATA_W => 8, MIF_FILE => "fc1_biases.mif")
        port map (
            clk  => clk,
            wr   => '0', -- Solo lectura
            addr => b_addr,
            din  => (others => '0'),
            dout => b_dout
        );

end architecture;