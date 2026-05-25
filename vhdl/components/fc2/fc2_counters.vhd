-- ============================================================
-- Modulo: fc2_counters.vhd (ESTRUCTURAL CON MUX INTEGRADO)
-- Descripcion: Contadores, calculo de direcciones indexadas
--              y multiplexor de direcciones de activacion (FC1).
-- ============================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fc2_counters is
    generic (
        N_IN  : integer := 64;
        N_OUT : integer := 10
    );
    port (
        clk             : in  std_logic;
        reset           : in  std_logic;
        
        -- Habilitadores de cuenta
        cnt_in_en       : in  std_logic;
        cnt_weight_en   : in  std_logic;
        cnt_neur_en     : in  std_logic;
        
        -- Reinicios directos sincronos
        cnt_in_clr      : in  std_logic;
        cnt_weight_clr  : in  std_logic;
        cnt_neur_clr    : in  std_logic;
        
        -- Linea de control para el MUX de direcciones
        act_addr_sel    : in  std_logic;
        
        -- Estado de los contadores
        cnt_in_val      : out std_logic_vector(5 downto 0);
        cnt_weight_val  : out std_logic_vector(5 downto 0);
        cnt_neur_val    : out std_logic_vector(3 downto 0);
        
        -- Flags de termino
        cnt_in_done     : out std_logic;
        cnt_weight_done : out std_logic;
        cnt_neur_done   : out std_logic;
        
        -- Direcciones calculadas y multiplexadas
        act_addr        : out std_logic_vector(5 downto 0); -- Agregado para el Top-Level
        w_addr          : out std_logic_vector(9 downto 0)
    );
end entity;

architecture structural of fc2_counters is

    -- Declaracion del componente reutilizable
    component contador is
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

    -- Señales locales de reset combinado (Reset Global OR Clear Local)
    signal rst_cnt_in     : std_logic;
    signal rst_cnt_weight : std_logic;
    signal rst_cnt_neur   : std_logic;

    -- Buses locales para interconexión interna
    signal s_cnt_in       : std_logic_vector(5 downto 0);
    signal s_cnt_weight   : std_logic_vector(5 downto 0);
    signal s_cnt_neur     : std_logic_vector(3 downto 0);
    
    -- Señal combinacional intermedia
    signal u_w_base       : unsigned(9 downto 0);

begin

    -- ── LOGICA DE RESET COMBINADO ───────────────────────────
    rst_cnt_in     <= reset or cnt_in_clr;
    rst_cnt_weight <= reset or cnt_weight_clr;
    rst_cnt_neur   <= reset or cnt_neur_clr;

    -- ── INSTANCIAS DE LOS CONTADORES GENÉRICOS ──────────────

    -- 1. Contador de Carga de Entrada (0 a 63)
    U_COUNTER_IN : contador
        generic map (
            N   => 6,
            MAX => N_IN - 1
        )
        port map (
            clk   => clk,
            reset => rst_cnt_in,
            en    => cnt_in_en,
            cnt   => s_cnt_in,
            done  => cnt_in_done
        );
    cnt_in_val <= s_cnt_in; -- Saca el bus al puerto de salida

    -- 2. Contador de Pesos Internos MAC (0 a 63)
    U_COUNTER_WEIGHT : contador
        generic map (
            N   => 6,
            MAX => N_IN - 1
        )
        port map (
            clk   => clk,
            reset => rst_cnt_weight,
            en    => cnt_weight_en,
            cnt   => s_cnt_weight,
            done  => cnt_weight_done
        );
    cnt_weight_val <= s_cnt_weight; -- Saca el bus al puerto de salida

    -- 3. Contador de Neuronas de Salida (0 a 9)
    U_COUNTER_NEUR : contador
        generic map (
            N   => 4,
            MAX => N_OUT - 1
        )
        port map (
            clk   => clk,
            reset => rst_cnt_neur,
            en    => cnt_neur_en,
            cnt   => s_cnt_neur,
            done  => cnt_neur_done
        );
    cnt_neur_val <= s_cnt_neur; -- Saca el bus al puerto de salida


    -- ── MUX DE DIRECCIONES DE ACTIVACIÓN (FC1) ──────────────
    -- act_addr_sel = '0' -> Modo escritura/carga (cnt_in)
    -- act_addr_sel = '1' -> Modo lectura/calculo MAC (cnt_weight)
    act_addr <= s_cnt_in when act_addr_sel = '0' else s_cnt_weight;


    -- ── ARITMÉTICA COMBINACIONAL DE DIRECCIONAMIENTO ─────────
    -- u_w_base = neurona * 64 + indice_peso
    u_w_base <= resize(unsigned(s_cnt_neur) * to_unsigned(N_IN, 6), 10) 
                 + resize(unsigned(s_cnt_weight), 10);
                 
    w_addr   <= std_logic_vector(u_w_base);

end architecture;