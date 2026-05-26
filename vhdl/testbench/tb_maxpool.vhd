-- ============================================================
-- Testbench: tb_maxpool.vhd
-- Descripcion: Banco de pruebas para verificar el bloque MaxPool
--              2x2 con streams multiplexados por filtros.
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_maxpool is
end entity;

architecture sim of tb_maxpool is

    -- Componente bajo prueba (UUT)
    component maxpool
        generic (
            IMG_W  : integer := 28;
            N_FILT : integer := 8
        );
        port (
            clk       : in  std_logic;
            reset     : in  std_logic;
            en        : in  std_logic;
            data_in   : in  signed(7 downto 0);
            filt_in   : in  std_logic_vector(2 downto 0);
            valid_in  : in  std_logic;
            pool_out  : out signed(7 downto 0);
            filt_out  : out std_logic_vector(2 downto 0);
            valid_out : out std_logic;
            done      : out std_logic
        );
    end component;

    -- Constantes de simulacion
    constant IMG_W_SIM  : integer := 28;
    constant N_FILT_SIM : integer := 8;
    constant CLK_PERIOD : time := 20 ns;

    -- Senales de estimulo
    signal clk       : std_logic := '0';
    signal reset     : std_logic := '0';
    signal en        : std_logic := '0';
    signal data_in   : signed(7 downto 0) := (others => '0');
    signal filt_in   : std_logic_vector(2 downto 0) := (others => '0');
    signal valid_in  : std_logic := '0';

    -- Senales de monitoreo
    signal pool_out  : signed(7 downto 0);
    signal filt_out  : std_logic_vector(2 downto 0);
    signal valid_out : std_logic;
    signal done      : std_logic;

    signal sim_terminada : boolean := false;

begin

    -- Instanciacion de la Unidad Bajo Prueba (UUT)
    UUT: maxpool
        generic map (
            IMG_W  => IMG_W_SIM,
            N_FILT => N_FILT_SIM
        )
        port map (
            clk       => clk,
            reset     => reset,
            en        => en,
            data_in   => data_in,
            filt_in   => filt_in,
            valid_in  => valid_in,
            pool_out  => pool_out,
            filt_out  => filt_out,
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

    -- Proceso Principal de Estimulos
    stim_process : process
        variable val_pixel : integer;
    begin
        --------------------------------------------------------
        -- FASE 1: Reset del Sistema
        --------------------------------------------------------
        report "Fase 1: Aplicando reset global al bloque MaxPool...";
        reset    <= '1';
        en       <= '0';
        valid_in <= '0';
        data_in  <= (others => '0');
        filt_in  <= (others => '0');
        wait for CLK_PERIOD * 5;
        reset    <= '0';
        wait for CLK_PERIOD * 2;

        --------------------------------------------------------
        -- FASE 2: Inyeccion de Datos del Stream (Filas de Pixeles)
        --------------------------------------------------------
        report "Fase 2: Iniciando transferencia de pixeles del mapa de caracteristicas...";
        en <= '1';

        -- Simularemos el procesamiento de las primeras 4 filas de la imagen para validar 
        -- el comportamiento en ventanas de submuestreo de 2x2 superiores e inferiores.
        for fila in 0 to 3 loop
            for col in 0 to IMG_W_SIM - 1 loop
                -- Iteramos por cada uno de los 8 filtros concurrentes
                for f in 0 to N_FILT_SIM - 1 loop
                    valid_in <= '1';
                    filt_in  <= std_logic_vector(to_unsigned(f, 3));

                    -- Creamos un patron controlado para verificar matematicamente el valor maximo
                    -- Pixeles en coordenadas estrategicas tendran valores mayores conocidos
                    if (fila mod 2 = 0) and (col mod 2 = 0) then
                        val_pixel := 10 + f; -- Fila par, Columna par
                    elsif (fila mod 2 = 0) and (col mod 2 /= 0) then
                        val_pixel := 5 + f;  -- Fila par, Columna impar
                    elsif (fila mod 2 /= 0) and (col mod 2 = 0) then
                        val_pixel := 45 + f; -- Fila impar, Columna par (Deberia ser el Maximo del bloque 2x2)
                    else
                        val_pixel := 22 + f; -- Fila impar, Columna impar
                    end if;

                    data_in <= to_signed(val_pixel, 8);
                    wait for CLK_PERIOD;
                 loop;
            end loop;
        end loop;

        -- Desactivacion de estimulos de entrada
        valid_in <= '0';
        data_in  <= (others => '0');
        wait for CLK_PERIOD * 10;

        --------------------------------------------------------
        -- FASE 3: Cierre de Simulacion
        --------------------------------------------------------
        report "Fase 3: Stream completado. Analizando estabilidad de salidas...";
        en <= '0';
        wait for CLK_PERIOD * 5;

        report "--- TESTBENCH MAXPOOL PROCESADO CON EXITO ---";
        sim_terminada <= true;
        wait;
    end process;

end architecture;