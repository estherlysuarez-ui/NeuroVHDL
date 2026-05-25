-- ============================================================
-- Modulo: salida_clasificacion.vhd (100% ESTRUCTURAL PURO)
-- Descripcion: Capa FC2 + Argmax sin procesos ni logica local.
-- ============================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity salida_clasificacion is
    generic (
        N_IN  : integer := 64;
        N_OUT : integer := 10;
        FRAC  : integer := 7
    );
    port (
        clk       : in  std_logic;
        reset     : in  std_logic;
        en        : in  std_logic;
        data_in   : in  signed(7 downto 0);
        valid_in  : in  std_logic;
        class_out : out std_logic_vector(3 downto 0);
        valid_out : out std_logic;
        done      : out std_logic
    );
end entity;

architecture structural of salida_clasificacion is

    -- ── COMPONENTES ──────────────────────────────────────────
    component fc2_controllers is
        port (
            clk, reset, en, valid_in : in  std_logic;
            cnt_in_done, cnt_weight_done, cnt_neur_done : in  std_logic;
            cnt_in_en, cnt_in_clr, cnt_weight_en, cnt_weight_clr : out std_logic;
            cnt_neur_en, cnt_neur_clr, act_wr, act_addr_sel, mac_en, mac_clr : out std_logic;
            argmax_update, argmax_reset, out_valid, layer_done : out std_logic
        );
    end component;

    component fc2_counters is
        generic (N_IN : integer; N_OUT : integer);
        port (
            clk, reset, cnt_in_en, cnt_weight_en, cnt_neur_en : in  std_logic;
            cnt_in_clr, cnt_weight_clr, cnt_neur_clr, act_addr_sel : in  std_logic;
            cnt_neur_val : out std_logic_vector(3 downto 0);
            cnt_in_done, cnt_weight_done, cnt_neur_done : out std_logic;
            act_addr : out std_logic_vector(5 downto 0);
            w_addr : out std_logic_vector(9 downto 0)
        );
    end component;

    component fc2_memories is
        port (
            clk : in std_logic;
            act_wr : in std_logic;
            act_addr : in std_logic_vector(5 downto 0);
            act_din : in std_logic_vector(7 downto 0);
            act_dout : out std_logic_vector(7 downto 0);
            w_addr : in std_logic_vector(9 downto 0);
            w_dout : out std_logic_vector(7 downto 0);
            b_addr : in std_logic_vector(3 downto 0);
            b_dout : out std_logic_vector(7 downto 0)
        );
    end component;

    component mult_add is
        port (
            clk, reset, en, clr : in  std_logic;
            a, b                : in  signed(7 downto 0);
            acc                 : out signed(23 downto 0)
        );
    end component;

    component fc2_datapath is
        port (
            clk, reset, argmax_reset, argmax_update, mac_en : in std_logic;
            mac_acc : in signed(23 downto 0);
            b_dout : in std_logic_vector(7 downto 0);
            cnt_neur_val : in std_logic_vector(3 downto 0);
            mac_en_d : out std_logic;
            class_out : out std_logic_vector(3 downto 0)
        );
    end component;

    -- ── CABLES INTERNOS ──────────────────────────────────────
    signal cnt_in_en, cnt_weight_en, cnt_neur_en : std_logic;
    signal cnt_in_clr, cnt_weight_clr, cnt_neur_clr : std_logic;
    signal cnt_in_done, cnt_weight_done, cnt_neur_done : std_logic;
    signal cnt_neur_val : std_logic_vector(3 downto 0);
    
    signal act_wr, act_addr_sel, mac_en, mac_en_d, mac_clr : std_logic;
    signal argmax_update, argmax_reset : std_logic;
    
    signal act_addr : std_logic_vector(5 downto 0);
    signal w_addr   : std_logic_vector(9 downto 0);
    signal act_dout, w_dout, b_dout : std_logic_vector(7 downto 0);
    
    signal mac_acc : signed(23 downto 0);

begin

    -- Instancia 1: FSM
    U_CTRL : fc2_controllers
        port map (
            clk => clk, reset => reset, en => en, valid_in => valid_in,
            cnt_in_done => cnt_in_done, cnt_weight_done => cnt_weight_done, cnt_neur_done => cnt_neur_done,
            cnt_in_en => cnt_in_en, cnt_in_clr => cnt_in_clr, cnt_weight_en => cnt_weight_en, cnt_weight_clr => cnt_weight_clr,
            cnt_neur_en => cnt_neur_en, cnt_neur_clr => cnt_neur_clr, act_wr => act_wr, act_addr_sel => act_addr_sel,
            mac_en => mac_en, mac_clr => mac_clr, argmax_update => argmax_update, argmax_reset => argmax_reset,
            out_valid => valid_out, layer_done => done
        );

    -- Instancia 2: Contadores (Con MUX de direcciones interno)
    U_COUNTERS : fc2_counters
        generic map (N_IN => N_IN, N_OUT => N_OUT)
        port map (
            clk => clk, reset => reset, cnt_in_en => cnt_in_en, cnt_weight_en => cnt_weight_en, cnt_neur_en => cnt_neur_en,
            cnt_in_clr => cnt_in_clr, cnt_weight_clr => cnt_weight_clr, cnt_neur_clr => cnt_neur_clr,
            act_addr_sel => act_addr_sel, cnt_neur_val => cnt_neur_val,
            cnt_in_done => cnt_in_done, cnt_weight_done => cnt_weight_done, cnt_neur_done => cnt_neur_done,
            act_addr => act_addr, w_addr => w_addr
        );

    -- Instancia 3: Memorias
    U_MEMS : fc2_memories
        port map (
            clk => clk, act_wr => act_wr, act_addr => act_addr, act_din => std_logic_vector(data_in), act_dout => act_dout,
            w_addr => w_addr, w_dout => w_dout, b_addr => cnt_neur_val, b_dout => b_dout
        );

    -- Instancia 4: Multiplicador-Acumulador
    U_MAC : mult_add
        port map (
            clk => clk, reset => reset, en => mac_en_d, clr => mac_clr,
            a => signed(act_dout), b => signed(w_dout), acc => mac_acc
        );

    -- Instancia 5: Camino de datos (Con registro de retardo interno)
    U_DATAPATH : fc2_datapath
        port map (
            clk           => clk,
            reset         => reset,
            argmax_reset  => argmax_reset,
            argmax_update => argmax_update,
            mac_en        => mac_en,
            mac_acc       => mac_acc,
            b_dout        => b_dout,
            cnt_neur_val  => cnt_neur_val,
            mac_en_d      => mac_en_d,
            class_out     => class_out
        );

end architecture;