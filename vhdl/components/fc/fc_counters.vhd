-- ============================================================
-- Modulo: fc_counters.vhd
-- Descripcion: Agrupacion de contadores para la capa oculta.
--              Incluye el calculo combinacional indexado 
--              para la direccion de memoria de pesos (w_addr).
-- ============================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fc_counters is
    generic (
        N_IN  : integer := 1352;  -- Entradas totales (13*13*8)
        N_OUT : integer := 64     -- Neuronas de salida
    );
    port (
        clk             : in  std_logic;
        reset           : in  std_logic;
        
        -- Habilitadores de cuenta desde el controlador
        cnt_in_en       : in  std_logic;
        cnt_weight_en   : in  std_logic;
        cnt_neur_en     : in  std_logic;
        
        -- Banderas de terminacion hacia el controlador
        cnt_in_done     : out std_logic;
        cnt_weight_done : out std_logic;
        cnt_neur_done   : out std_logic;
        
        -- Direcciones calculadas para las memorias
        act_addr_load   : out std_logic_vector(10 downto 0);
        act_addr_calc   : out std_logic_vector(10 downto 0);
        w_addr          : out std_logic_vector(16 downto 0);
        b_addr          : out std_logic_vector(5 downto 0)
    );
end entity;

architecture rtl of fc_counters is

    -- ── Declaracion del Componente Reutilizable ─────────────────
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

    -- ── Buses Internos en formato std_logic_vector ──────────────
    signal s_cnt_in     : std_logic_vector(10 downto 0);
    signal s_cnt_weight : std_logic_vector(10 downto 0);
    signal s_cnt_neur   : std_logic_vector(5 downto 0);

    -- ── Señales para operaciones aritmeticas ────────────────────
    signal u_cnt_neur   : unsigned(5 downto 0);
    signal u_cnt_weight : unsigned(10 downto 0);
    signal u_w_base     : unsigned(16 downto 0);

begin

    -- ── Instancia 1: Contador para Fase de Carga (S_LOAD) ────────
    -- Se cambio la etiqueta a U_COUNTER_IN para evitar conflictos
    U_COUNTER_IN : contador
        generic map (N => 11, MAX => N_IN - 1)
        port map (
            clk   => clk,
            reset => reset,
            en    => cnt_in_en,
            cnt   => s_cnt_in,
            done  => cnt_in_done
        );

    -- ── Instancia 2: Contador de Entradas por Neurona (S_CALC) ────
    -- Se cambio la etiqueta a U_COUNTER_WEIGHT para evitar conflictos con la señal u_cnt_weight
    U_COUNTER_WEIGHT : contador
        generic map (N => 11, MAX => N_IN - 1)
        port map (
            clk   => clk,
            reset => reset,
            en    => cnt_weight_en,
            cnt   => s_cnt_weight,
            done  => cnt_weight_done
        );

    -- ── Instancia 3: Contador de Neuronas (S_OUT) ────────────────
    -- Se cambio la etiqueta a U_COUNTER_NEUR para evitar conflictos con la señal u_cnt_neur
    U_COUNTER_NEUR : contador
        generic map (N => 6, MAX => N_OUT - 1)
        port map (
            clk   => clk,
            reset => reset,
            en    => cnt_neur_en,
            cnt   => s_cnt_neur,
            done  => cnt_neur_done
        );

    -- ── Conversiones a Unsigned para Aritmetica ─────────────────
    u_cnt_neur   <= unsigned(s_cnt_neur);
    u_cnt_weight <= unsigned(s_cnt_weight);

    -- ── Calculo Combinacional de Direccion de Pesos (w_addr) ─────
    u_w_base <= (u_cnt_neur * to_unsigned(N_IN, 11)) + resize(u_cnt_weight, 17);

    -- ── Asignacion de Salidas ───────────────────────────────────
    act_addr_load <= s_cnt_in;
    act_addr_calc <= s_cnt_weight;
    b_addr        <= s_cnt_neur;
    w_addr        <= std_logic_vector(u_w_base);

end architecture;