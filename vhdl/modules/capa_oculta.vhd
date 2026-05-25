-- ============================================================
-- Modulo: capa_oculta.vhd (TOP-LEVEL ESTRUCTURAL OPTIMIZADO)
-- Descripcion: Capa completamente conectada FC1: 1352->64
--              Utiliza el bloque unificado 'fc_memories' para
--              limpiar la estructura de buses y componentes.
-- ============================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity capa_oculta is
    generic (
        N_IN  : integer := 1352;  -- 13*13*8 activaciones de entrada
        N_OUT : integer := 64;    -- Neuronas en la capa oculta
        FRAC  : integer := 7      -- Fraccion Q1.7
    );
    port (
        clk       : in  std_logic;
        reset     : in  std_logic;
        en        : in  std_logic;
        data_in   : in  signed(7 downto 0);
        valid_in  : in  std_logic;
        fc_out    : out signed(7 downto 0);
        valid_out : out std_logic;
        done      : out std_logic
    );
end entity;

architecture structural of capa_oculta is

    -- ── DECLARACIÓN DE COMPONENTES ───────────────────────────
    
    -- 1. Controlador (FSM)
    component fc_controller is
        port (
            clk, reset, en  : in  std_logic;
            valid_in        : in  std_logic;
            cnt_in_done     : in  std_logic;
            cnt_weight_done : in  std_logic;
            cnt_neur_done   : in  std_logic;
            act_wr          : out std_logic;
            act_addr_sel    : out std_logic;
            cnt_in_en       : out std_logic;
            cnt_weight_en   : out std_logic;
            cnt_neur_en     : out std_logic;
            mac_en          : out std_logic;
            mac_clr         : out std_logic;
            bias_read_en    : out std_logic;
            out_valid       : out std_logic;
            layer_done      : out std_logic
        );
    end component;

    -- 2. Bloque de Contadores y Calculo de Direcciones
    component fc_counters is
        generic (
            N_IN  : integer;
            N_OUT : integer
        );
        port (
            clk             : in  std_logic;
            reset           : in  std_logic;
            cnt_in_en       : in  std_logic;
            cnt_weight_en   : in  std_logic;
            cnt_neur_en     : in  std_logic;
            cnt_in_done     : out std_logic;
            cnt_weight_done : out std_logic;
            cnt_neur_done   : out std_logic;
            act_addr_load   : out std_logic_vector(10 downto 0);
            act_addr_calc   : out std_logic_vector(10 downto 0);
            w_addr          : out std_logic_vector(16 downto 0);
            b_addr          : out std_logic_vector(5 downto 0)
        );
    end component;

    -- 3. Bloque Unificado de Memorias (Sustituye a las 3 ram_sp individuales)
    component fc_memories is
        port (
            clk        : in  std_logic;
            act_wr     : in  std_logic;
            act_addr   : in  std_logic_vector(10 downto 0);
            act_din    : in  std_logic_vector(7 downto 0);
            act_dout   : out std_logic_vector(7 downto 0);
            w_addr     : in  std_logic_vector(16 downto 0);
            w_dout     : out std_logic_vector(7 downto 0);
            b_addr     : in  std_logic_vector(5 downto 0);
            b_dout     : out std_logic_vector(7 downto 0)
        );
    end component;

    -- 4. Multiplicador - Acumulador (MAC)
    component mult_add is
        port (
            clk, reset, en, clr : in  std_logic;
            a, b                : in  signed(7 downto 0);
            acc                 : out signed(23 downto 0)
        );
    end component;

    -- 5. Registro Genérico para Pipelines y Salidas
    component registro is
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

    -- ── INTERCONEXIONES (BUSES Y SEÑALES INTERNAS) ───────────
    
    -- Señales de Control y Flags de los Contadores
    signal cnt_in_en, cnt_weight_en, cnt_neur_en : std_logic;
    signal cnt_in_done, cnt_weight_done, cnt_neur_done : std_logic;
    
    -- Buses de Direccionamiento de Memorias
    signal act_addr_sel : std_logic;
    signal act_addr     : std_logic_vector(10 downto 0);
    signal act_addr_load: std_logic_vector(10 downto 0);
    signal act_addr_calc: std_logic_vector(10 downto 0);
    signal w_addr       : std_logic_vector(16 downto 0);
    signal b_addr       : std_logic_vector(5 downto 0);

    -- Buses de Datos e interfaces de Memoria
    signal act_wr       : std_logic;
    signal act_dout     : std_logic_vector(7 downto 0);
    signal w_dout       : std_logic_vector(7 downto 0);
    signal b_dout       : std_logic_vector(7 downto 0);

    -- Señales del Canal de Datos del MAC
    signal mac_en       : std_logic;
    signal mac_en_d     : std_logic;
    signal mac_clr      : std_logic;
    signal mac_acc      : signed(23 downto 0);
    signal biased_acc   : signed(23 downto 0);
    
    -- Señales de Salida y Sincronismo
    signal ctrl_valid   : std_logic;
    signal relu_out     : std_logic_vector(7 downto 0);
    signal s_fc_out     : std_logic_vector(7 downto 0);

begin

    -- ── MUX: Seleccion de Direccion de la RAM de Activaciones ──
    -- '0' = Modo Carga (Escribe datos de entrada) | '1' = Modo Calculo (Lee hacia el MAC)
    act_addr <= act_addr_load when act_addr_sel = '0' else act_addr_calc;

    -- ── 1. INSTANCIA: CONTROLADOR (FSM) ──────────────────────
    U_FC_CTRL : fc_controller
        port map (
            clk             => clk,
            reset           => reset,
            en              => en,
            valid_in        => valid_in,
            cnt_in_done     => cnt_in_done,
            cnt_weight_done => cnt_weight_done,
            cnt_neur_done   => cnt_neur_done,
            act_wr          => act_wr,
            act_addr_sel    => act_addr_sel,
            cnt_in_en       => cnt_in_en,
            cnt_weight_en   => cnt_weight_en,
            cnt_neur_en     => cnt_neur_en,
            mac_en          => mac_en,
            mac_clr         => mac_clr,
            bias_read_en    => open,
            out_valid       => ctrl_valid,
            layer_done      => done
        );

    -- ── 2. INSTANCIA: BLOQUE DE CONTADORES ───────────────────
    U_FC_COUNTERS : fc_counters
        generic map (
            N_IN  => N_IN,
            N_OUT => N_OUT
        )
        port map (
            clk             => clk,
            reset           => reset,
            cnt_in_en       => cnt_in_en,
            cnt_weight_en   => cnt_weight_en,
            cnt_neur_en     => cnt_neur_en,
            cnt_in_done     => cnt_in_done,
            cnt_weight_done => cnt_weight_done,
            cnt_neur_done   => cnt_neur_done,
            act_addr_load   => act_addr_load,
            act_addr_calc   => act_addr_calc,
            w_addr          => w_addr,
            b_addr          => b_addr
        );

    -- ── 3. INSTANCIA: SUBSISTEMA DE MEMORIAS UNIFICADO ────────
    -- Agrupa de manera interna las tres RAMs de tu arquitectura.
    U_MEMORIES : fc_memories
        port map (
            clk        => clk,
            act_wr     => act_wr,
            act_addr   => act_addr,
            act_din    => std_logic_vector(data_in),
            act_dout   => act_dout,
            w_addr     => w_addr,
            w_dout     => w_dout,
            b_addr     => b_addr,
            b_dout     => b_dout
        );

    -- ── 4. INSTANCIA: MULTIPLICADOR-ACUMULADOR (MAC) ─────────
    U_MAC : mult_add
        port map (
            clk   => clk,
            reset => reset,
            en    => mac_en_d, -- Usa la señal retardada de control
            clr   => mac_clr,
            a     => signed(act_dout),
            b     => signed(w_dout),
            acc   => mac_acc
        );

    -- ── OPERACIONES COMBINACIONALES POST-MAC ─────────────────
    
    -- Extension de signo del Bias de 8 bits a 24 bits y suma al acumulador
    biased_acc <= mac_acc + resize(signed(b_dout), 24);

    -- Funcion de Activacion ReLU + Truncado a Formato Fijo Q1.7
    relu_out <= std_logic_vector(biased_acc(FRAC+7 downto FRAC)) when biased_acc(23) = '0' 
                else (others => '0');

    -- ── 5. INSTANCIAS: REGISTROS (RETARDOS Y ETAPAS DE SALIDA) ─

    -- Registro para retrasar 'mac_en' 1 ciclo de reloj (Compensar latencia de lectura BRAM)
    U_REG_MAC_EN : registro
        generic map (N => 1)
        port map (
            clk   => clk,
            reset => reset,
            en    => '1',
            d(0)  => mac_en,
            q(0)  => mac_en_d
        );

    -- Registro de Sostén para el Bus de Datos de Salida (fc_out)
    U_REG_FC_OUT : registro
        generic map (N => 8)
        port map (
            clk   => clk,
            reset => reset,
            en    => ctrl_valid,
            d     => relu_out,
            q     => s_fc_out
        );

    -- Registro para la señal de datos validos de salida (valid_out)
    U_REG_VALID_OUT : registro
        generic map (N => 1)
        port map (
            clk   => clk,
            reset => reset,
            en    => '1',
            d(0)  => ctrl_valid,
            q(0)  => valid_out
        );

    -- Asignacion final del bus de datos convertido a signed
    fc_out <= signed(s_fc_out);

end architecture;