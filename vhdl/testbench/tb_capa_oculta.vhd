-- ============================================================
-- Testbench: tb_capa_oculta.vhd (AUTO-DEPURABLE)
-- Descripcion: Banco de pruebas para validar la capa FC1
--              optimizada con aserciones en tiempo real.
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_capa_oculta is
end entity;

architecture sim of tb_capa_oculta is

    -- Componente Bajo Prueba (UUT)
    component capa_oculta
        generic (
            N_IN  : integer := 1352;
            N_OUT : integer := 64;
            FRAC  : integer := 7
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
    end component;

    -- Configuracion Escalada para Simulación Rapida
    constant N_IN_SIM  : integer := 6;  -- 6 Activaciones de entrada
    constant N_OUT_SIM : integer := 3;  -- 3 Neuronas de salida
    constant FRAC_SIM  : integer := 7;
    constant CLK_PERIOD: time := 20 ns;

    -- Senales de estimulo
    signal clk       : std_logic := '0';
    signal reset     : std_logic := '0';
    signal en        : std_logic := '0';
    signal data_in   : signed(7 downto 0) := (others => '0');
    signal valid_in  : std_logic := '0';

    -- Senales de monitoreo
    signal fc_out    : signed(7 downto 0);
    signal valid_out : std_logic;
    signal done      : std_logic;

    signal sim_terminada : boolean := false;

begin

    -- Instanciacion de la Capa Oculta (UUT)
    UUT: capa_oculta
        generic map (
            N_IN  => N_IN_SIM,
            N_OUT => N_OUT_SIM,
            FRAC  => FRAC_SIM
        )
        port map (
            clk       => clk,
            reset     => reset,
            en        => en,
            data_in   => data_in,
            valid_in  => valid_in,
            fc_out    => fc_out,
            valid_out => valid_out,
            done      => done
        );

    -- Generador de Reloj (50 MHz)
    clk_process : process
    begin
        while not sim_terminada loop
            clk <= '0';
            wait for CLK_PERIOD / 2;
            clk <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process;

    -- ========================================================
    -- PROCESO MONITOR: ASERCIONES EN CONSOLA EN TIEMPO REAL
    -- ========================================================
    monitor_process : process(clk)
    begin
        if rising_edge(clk) then
            if reset = '0' then
                -- REGLA 1: Proteccion contra datos basura en valid_out
                if valid_out = '1' then
                    assert (en = '1')
                        report "FALLO CRITICO: Capa entregando outputs validos con el modulo deshabilitado (en='0')"
                        severity error;
                end if;

                -- REGLA 2: Coherencia de banderas de terminacion
                if done = '1' then
                    assert (valid_out = '0')
                        report "ADVERTENCIA: done y valid_out activos simultaneamente. Posible desalineamiento de pipeline"
                        severity warning;
                end if;
            end if;
        end if;
    end process;

    -- Proceso Principal de Estimulos
    stim_process : process
    begin
        --------------------------------------------------------
        -- FASE 1: Inicializacion y Reset
        --------------------------------------------------------
        report "Fase 1: Aplicando reset síncrono al bloque Capa Oculta...";
        reset    <= '1';
        en       <= '0';
        valid_in <= '0';
        data_in  <= (others => '0');
        wait for CLK_PERIOD * 4;
        reset    <= '0';
        wait for CLK_PERIOD * 2;

        --------------------------------------------------------
        -- FASE 2: Modo Carga (Escribir activaciones en RAM)
        --------------------------------------------------------
        report "Fase 2: Entrando en Modo Carga. Guardando datos del stream anterior...";
        en <= '1';
        wait for CLK_PERIOD;

        -- Inyectamos valores secuenciales fijos para simular el MaxPool (ej: 2, 4, 6...)
        for i in 1 to N_IN_SIM loop
            valid_in <= '1';
            data_in  <= to_signed(i * 2, 8);
            wait for CLK_PERIOD;
        end loop;

        -- Cerramos el grifo de datos de entrada
        valid_in <= '0';
        data_in  <= (others => '0');
        
        --------------------------------------------------------
        -- FASE 3: Espera del proceso de Computo (MAC + ReLU)
        --------------------------------------------------------
        report "Fase 3: Datos cargados. Monitoreando ejecucion interna del MAC y activacion ReLU...";
        
        -- Damos suficiente margen de tiempo para que los contadores internos recorran 
        -- todas las neuronas calculando los productos punto distributivos
        wait until done = '1' for CLK_PERIOD * (N_IN_SIM * N_OUT_SIM + 20);

        assert done = '1' 
            report "FALLO TOTAL: El bloque quedo colgado y nunca levanto la bandera DONE" 
            severity failure;

        --------------------------------------------------------
        -- FASE 4: Validacion de estabilidad post-calculo
        --------------------------------------------------------
        report "Fase 4: Procesamiento completado. Verificando limpieza de buses...";
        wait for CLK_PERIOD * 5;
        
        -- Deshabilitamos el bloque por completo
        en <= '0';
        wait for CLK_PERIOD * 5;

        --------------------------------------------------------
        -- Fin de la simulacion
        --------------------------------------------------------
        report "--- TESTBENCH CAPA OCULTA PROCESADO CON EXITO ---";
        sim_terminada <= true;
        wait;
    end process;

end architecture;