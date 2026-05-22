library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity capa_oculta is
    generic (
        N_IN   : integer := 1352;
        N_OUT  : integer := 64;
        FRAC   : integer := 7
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

architecture rtl of capa_oculta is

    component ram_sp
        generic (ADDR_W, DATA_W : integer; MIF_FILE : string);
        port (clk  : in  std_logic;
              wr   : in  std_logic;
              addr : in  std_logic_vector(ADDR_W-1 downto 0);
              din  : in  std_logic_vector(DATA_W-1 downto 0);
              dout : out std_logic_vector(DATA_W-1 downto 0));
    end component;

    component mult_add
        port (clk, reset, en, clr : in  std_logic;
              a, b                : in  signed(7 downto 0);
              acc                 : out signed(23 downto 0));
    end component;

    -- Activaciones flatten (1352 x 8 bits)
    signal act_wr   : std_logic := '0';
    signal act_addr : std_logic_vector(10 downto 0);
    signal act_din  : std_logic_vector(7 downto 0);
    signal act_dout : std_logic_vector(7 downto 0);

    -- Pesos FC1 (86528 x 8 bits, 17 bits de direccion)
    signal w_addr   : std_logic_vector(16 downto 0);
    signal w_dout   : std_logic_vector(7 downto 0);

    -- MAC
    signal mac_en  : std_logic := '0';
    signal mac_clr : std_logic := '0';
    signal mac_acc : signed(23 downto 0);

    -- Contadores
    signal cnt_in     : unsigned(10 downto 0) := (others => '0');
    signal cnt_neur   : unsigned(5 downto 0)  := (others => '0');
    signal cnt_weight : unsigned(10 downto 0) := (others => '0');

    -- Salidas registradas
    signal r_out   : signed(7 downto 0) := (others => '0');
    signal r_valid : std_logic := '0';
    signal r_done  : std_logic := '0';

    -- FSM
    type t_state is (S_LOAD, S_CALC, S_OUT, S_DONE);
    signal state : t_state := S_LOAD;

    -- Bias FC1 (placeholder, reemplazar con valores reales)
    type t_bias is array(0 to N_OUT-1) of signed(7 downto 0);
    constant BIAS_FC1 : t_bias := (others => to_signed(0, 8));

    -- Producto: cnt_neur(6 bits) * N_IN(11 bits) = 17 bits exactos
    signal w_base : unsigned(16 downto 0);

begin

    U_ACT_RAM : ram_sp
        generic map (ADDR_W => 11, DATA_W => 8, MIF_FILE => "none")
        port map (clk => clk, wr => act_wr, addr => act_addr,
                  din => act_din, dout => act_dout);

    U_W_RAM : ram_sp
        generic map (ADDR_W => 17, DATA_W => 8, MIF_FILE => "fc1_weights.mif")
        port map (clk => clk, wr => '0', addr => w_addr,
                  din => (others => '0'), dout => w_dout);

    U_MAC : mult_add
        port map (clk => clk, reset => reset, en => mac_en, clr => mac_clr,
                  a => signed(act_dout), b => signed(w_dout), acc => mac_acc);

    -- FIX: calcular direccion de peso como senal de 17 bits
    -- resize a 17 bits antes de multiplicar para evitar truncamiento
    -- cnt_neur es 6 bits, to_unsigned(N_IN,11) es 11 bits -> producto = 17 bits
    w_base <= cnt_neur * to_unsigned(N_IN, 11) + resize(cnt_weight, 17);
    w_addr <= std_logic_vector(w_base);

    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                state      <= S_LOAD;
                cnt_in     <= (others => '0');
                cnt_neur   <= (others => '0');
                cnt_weight <= (others => '0');
                act_wr     <= '0';
                mac_en     <= '0';
                mac_clr    <= '0';
                r_valid    <= '0';
                r_done     <= '0';
            else
                mac_clr <= '0';
                r_valid <= '0';

                case state is

                    when S_LOAD =>
                        if en = '1' and valid_in = '1' then
                            act_wr   <= '1';
                            act_addr <= std_logic_vector(cnt_in);
                            act_din  <= std_logic_vector(data_in);
                            if cnt_in = N_IN-1 then
                                cnt_in  <= (others => '0');
                                act_wr  <= '0';
                                mac_clr <= '1';
                                state   <= S_CALC;
                            else
                                cnt_in <= cnt_in + 1;
                            end if;
                        end if;

                    when S_CALC =>
                        -- w_base/w_addr se actualizan combinacionalmente
                        act_addr <= std_logic_vector(cnt_weight);
                        mac_en   <= '1';
                        if cnt_weight = N_IN-1 then
                            mac_en     <= '0';
                            cnt_weight <= (others => '0');
                            state      <= S_OUT;
                        else
                            cnt_weight <= cnt_weight + 1;
                        end if;

                    when S_OUT =>
                        -- FIX: usar FRAC generico en lugar de literal 7
                        -- ReLU inline: si mac_acc >> FRAC > 0 -> pasar, si no -> 0
                        if mac_acc(23) = '0' then
                            r_out <= mac_acc(FRAC+7 downto FRAC);  -- truncar >> FRAC
                        else
                            r_out <= (others => '0');               -- ReLU
                        end if;
                        r_out   <= r_out + BIAS_FC1(to_integer(cnt_neur));
                        r_valid <= '1';
                        mac_clr <= '1';
                        if cnt_neur = N_OUT-1 then
                            cnt_neur <= (others => '0');
                            r_done   <= '1';
                            state    <= S_DONE;
                        else
                            cnt_neur <= cnt_neur + 1;
                            state    <= S_CALC;
                        end if;

                    when S_DONE =>
                        r_done <= '0';
                        if en = '0' then state <= S_LOAD; end if;

                    when others => state <= S_LOAD;
                end case;
            end if;
        end if;
    end process;

    fc_out    <= r_out;
    valid_out <= r_valid;
    done      <= r_done;

end architecture;