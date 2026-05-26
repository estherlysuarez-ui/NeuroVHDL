-- ============================================================
-- Testbench: tb_fsm_control.vhd (VERSION AUTO-DEPURABLE)
-- Descripcion: Banco de pruebas con aserciones rigurosas para
--              capturar fallos de concurrencia en la FSM.
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;

entity tb_fsm_control is
end entity;

architecture sim of tb_fsm_control is

    -- Unidad Bajo Prueba (UUT)
    component fsm_control
        port (
            clk         : in  std_logic;
            reset       : in  std_logic;
            start       : in  std_logic;
            done_entrada: in  std_logic;
            done_conv   : in  std_logic;
            done_pool   : in  std_logic;
            done_fc     : in  std_logic;
            done_out    : in  std_logic;
            en_entrada  : out std_logic;
            en_conv     : out std_logic;
            en_pool     : out std_logic;
            en_fc       : out std_logic;
            en_out      : out std_logic;
            state_dbg   : out std_logic_vector(7 downto 0)
        );
    end component;

    -- Constantes
    constant CLK_PERIOD : time := 20 ns;

    -- Senales de estimulo
    signal clk          : std_logic := '0';
    signal reset        : std_logic := '0';
    signal start        : std_logic := '0';
    signal done_entrada : std_logic := '0';
    signal done_conv    : std_logic := '0';
    signal done_pool    : std_logic := '0';
    signal done_fc      : std_logic := '0';
    signal done_out     : std_logic := '0';

    -- Senales de monitoreo
    signal en_entrada   : std_logic;
    signal en_conv      : std_logic;
    signal en_pool      : std_logic;
    signal en_fc        : std_logic;
    signal en_out       : std_logic;
    signal state_dbg    : std_logic_vector(7 downto 0);

    signal sim_terminada : boolean := false;

begin

    -- Instanciacion de la FSM
    UUT: fsm_control
        port map (
            clk          => clk,
            reset        => reset,
            start        => start,
            done_entrada => done_entrada,
            done_conv    => done_conv,
            done_pool    => done_pool,
            done_fc      => done_fc,
            done_out     => done_out,
            en_entrada   => en_entrada,
            en_conv      => en_conv,
            en_pool      => en_pool,
            en_fc        => en_fc,
            en_out       => en_out,
            state_dbg    => state_dbg
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
    -- PROCESO MONITOR: VERIFICACIÓN EN TIEMPO REAL POR CONSOLA
    -- ========================================================
    monitor_process : process(clk)
    begin
        if rising_edge(clk) then
            if reset = '0' then
                -- REGLA 1: Concurrencia Critica en S_ENTRADA
                if state_dbg = "00000010" then
                    assert (en_entrada = '1' and en_conv = '1')
                        report "FALLO CRITICO CONSOLA: S_ENTRADA activo pero en_entrada o en_conv estan caidos (Falta Concurrencia)"
                        severity error;
                end if;

                -- REGLA 2: Autonomia de la Convolucion en S_CONV
                if state_dbg = "00000100" then
                    assert (en_entrada = '0' and en_conv = '1')
                        report "FALLO CRITICO CONSOLA: S_CONV activo pero en_entrada sigue encendido o en_conv se apago prematuramente"
                        severity error;
                end if;

                -- REGLA 3: Exclusividad Mutua e Inactividad Cruzada (Cero Coincidencias)
                if state_dbg = "00001000" then -- S_POOL
                    assert (en_entrada = '0' and en_conv = '0' and en_pool = '1' and en_fc = '0' and en_out = '0')
                        report "FALLO CRITICO CONSOLA: Solapamiento ilegal de habilitadores detectado durante la etapa S_POOL"
                        severity error;
                end if;

                if state_dbg = "00010000" then -- S_FC1
                    assert (en_entrada = '0' and en_conv = '0' and en_pool = '0' and en_fc = '1' and en_out = '0')
                        report "FALLO CRITICO CONSOLA: Solapamiento ilegal de habilitadores detectado durante la etapa S_FC1"
                        severity error;
                end if;

                if state_dbg = "00100000" then -- S_OUT
                    assert (en_entrada = '0' and en_conv = '0' and en_pool = '0' and en_fc = '0' and en_out = '1')
                        report "FALLO CRITICO CONSOLA: Solapamiento ilegal de habilitadores detectado durante la etapa S_OUT"
                        severity error;
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
        report "Fase 1: Aplicando reset y verificando estado IDLE...";
        reset <= '1';
        start <= '0';
        done_entrada <= '0'; done_conv <= '0'; done_pool <= '0'; done_fc <= '0'; done_out <= '0';
        wait for CLK_PERIOD * 3;
        reset <= '0';
        wait for CLK_PERIOD;

        assert state_dbg = "00000001" report "Error: No se inicio en S_IDLE" severity failure;

        --------------------------------------------------------
        -- FASE 2: Flujo Normal del Pipeline (Secuencia MNIST)
        --------------------------------------------------------
        report "Fase 2: Lanzando pulso de START...";
        start <= '1';
        wait for CLK_PERIOD;
        start <= '0';
        wait for CLK_PERIOD * 2; -- Permitir asentamiento del estado S_ENTRADA

        report "Verificando ejecucion en paralelo: Entrada -> Convolucion...";
        wait for CLK_PERIOD * 5; 

        -- Finaliza transferencia de pixeles de memoria
        report "Enviando done_entrada -> Transicionando a S_CONV...";
        done_entrada <= '1';
        wait for CLK_PERIOD;
        done_entrada <= '0';
        wait for CLK_PERIOD * 2;
        
        report "Verificando vaciado exclusivo del pipeline de Convolucion...";
        wait for CLK_PERIOD * 5; 

        -- Finaliza el procesamiento convolucional
        report "Enviando done_conv -> Transicionando a S_POOL...";
        done_conv <= '1';
        wait for CLK_PERIOD;
        done_conv <= '0';
        wait for CLK_PERIOD * 2;

        report "Verificando aislamiento de la etapa Max-Pooling...";
        wait for CLK_PERIOD * 5;

        -- Finaliza el submuestreo MaxPool
        report "Enviando done_pool -> Transicionando a S_FC1...";
        done_pool <= '1';
        wait for CLK_PERIOD;
        done_pool <= '0';
        wait for CLK_PERIOD * 2;

        report "Verificando aislamiento de la etapa Fully-Connected...";
        wait for CLK_PERIOD * 5;

        -- Finaliza calculo de neuronas de salida
        report "Enviando done_fc -> Transicionando a S_OUT...";
        done_fc <= '1';
        wait for CLK_PERIOD;
        done_fc <= '0';
        wait for CLK_PERIOD * 2;

        report "Verificando aislamiento de la etapa de Salida...";
        wait for CLK_PERIOD * 5;

        -- Finaliza salida del resultado final de prediccion
        report "Enviando done_out -> Transicionando a S_DONE y retorno automatico...";
        done_out <= '1';
        wait for CLK_PERIOD;
        done_out <= '0';
        wait for CLK_PERIOD * 3; 

        assert state_dbg = "00000001" report "Error: No retorno a S_IDLE al finalizar" severity error;

        --------------------------------------------------------
        -- FASE 3: Verificacion del Reset en mitad de ejecucion
        --------------------------------------------------------
        report "Fase 3: Probando interrupcion por Reset en caliente...";
        start <= '1';
        wait for CLK_PERIOD;
        start <= '0';
        wait for CLK_PERIOD * 2; 
        
        reset <= '1'; 
        wait for CLK_PERIOD;
        reset <= '0';
        wait for CLK_PERIOD;

        assert state_dbg = "00000001" report "Error: El reset no devolvio el sistema a IDLE" severity error;

        --------------------------------------------------------
        -- Fin de la simulacion
        --------------------------------------------------------
        report "--- TESTBENCH CONTROLADOR FSM PROCESADO CON EXITO ---";
        sim_terminada <= true;
        wait;
    end process;

end architecture;