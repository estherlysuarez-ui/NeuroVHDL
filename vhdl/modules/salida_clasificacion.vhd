-- ============================================================
-- Modulo: salida_clasificacion.vhd
-- Descripcion: Capa FC2: 64->10 clases + argmax.
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

architecture rtl of salida_clasificacion is

    component ram_sp
        generic (ADDR_W, DATA_W : integer; MIF_FILE : string);
        port (clk : in std_logic; wr : in std_logic;
              addr : in std_logic_vector(ADDR_W-1 downto 0);
              din  : in std_logic_vector(DATA_W-1 downto 0);
              dout : out std_logic_vector(DATA_W-1 downto 0));
    end component;

    component mult_add
        port (clk,reset,en,clr : in std_logic;
              a,b : in signed(7 downto 0);
              acc : out signed(23 downto 0));
    end component;

    component comparador
        generic (N : integer);
        port (a,b : in signed(N-1 downto 0);
              mayor,igual : out std_logic;
              relu : out signed(N-1 downto 0));
    end component;

    signal act_wr    : std_logic := '0';
    signal act_addr  : std_logic_vector(5 downto 0) := (others => '0');
    signal act_din   : std_logic_vector(7 downto 0);
    signal act_dout  : std_logic_vector(7 downto 0);

    signal w_addr    : std_logic_vector(9 downto 0) := (others => '0');
    signal w_dout    : std_logic_vector(7 downto 0);

    signal cnt_in    : unsigned(5 downto 0)  := (others => '0');
    signal cnt_neur  : unsigned(3 downto 0)  := (others => '0');
    signal cnt_weight: unsigned(5 downto 0)  := (others => '0');

    signal mac_en    : std_logic := '0';
    signal mac_clr   : std_logic := '0';
    signal mac_a     : signed(7 downto 0) := (others => '0');
    signal mac_b     : signed(7 downto 0) := (others => '0');
    signal mac_acc   : signed(23 downto 0);

    signal max_val   : signed(23 downto 0) := (others => '1');
    signal max_idx   : unsigned(3 downto 0) := (others => '0');

    signal cmp_mayor : std_logic;
    signal dummy_i   : std_logic;
    signal dummy_r   : signed(23 downto 0);

    signal r_class   : std_logic_vector(3 downto 0) := (others => '0');
    signal r_valid   : std_logic := '0';
    signal r_done    : std_logic := '0';

    type t_state is (S_LOAD, S_CALC, S_BIAS, S_ARGMAX, S_OUT, S_DONE);
    signal state : t_state := S_LOAD;

begin

    U_ACT : ram_sp
        generic map (ADDR_W=>6, DATA_W=>8, MIF_FILE=>"")
        port map (clk=>clk, wr=>act_wr, addr=>act_addr,
                  din=>act_din, dout=>act_dout);

    U_W2 : ram_sp
        generic map (ADDR_W=>10, DATA_W=>8, MIF_FILE=>"fc2_weights.mif")
        port map (clk=>clk, wr=>'0', addr=>w_addr,
                  din=>"00000000", dout=>w_dout);

    U_MAC : mult_add
        port map (clk=>clk, reset=>reset, en=>mac_en, clr=>mac_clr,
                  a=>mac_a, b=>mac_b, acc=>mac_acc);

    U_CMP : comparador
        generic map (N=>24)
        port map (a=>mac_acc, b=>max_val,
                  mayor=>cmp_mayor, igual=>dummy_i, relu=>dummy_r);

    process(clk)
        variable w_base : unsigned(9 downto 0);
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
                max_val    <= (23=>'1', others=>'0');
                max_idx    <= (others => '0');
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
                                cnt_in   <= (others => '0');
                                act_wr   <= '0';
                                mac_clr  <= '1';
                                max_val  <= (23=>'1', others=>'0');
                                max_idx  <= (others => '0');
                                state    <= S_CALC;
                            else
                                cnt_in <= cnt_in + 1;
                            end if;
                        end if;

                    when S_CALC =>
                        act_addr <= std_logic_vector(cnt_weight);
                        w_base := resize((resize(cnt_neur, 10) * to_unsigned(N_IN, 10)), 10) + resize(cnt_weight, 10);
                        w_addr   <= std_logic_vector(w_base);
                        mac_a    <= signed(act_dout);
                        mac_b    <= signed(w_dout);
                        mac_en   <= '1';
                        if cnt_weight = N_IN-1 then
                            mac_en     <= '0';
                            cnt_weight <= (others => '0');
                            state      <= S_BIAS;
                        else
                            cnt_weight <= cnt_weight + 1;
                        end if;

                    when S_BIAS =>
                        state <= S_ARGMAX;

                    when S_ARGMAX =>
                        if cmp_mayor = '1' then
                            max_val <= mac_acc;
                            max_idx <= cnt_neur;
                        end if;
                        mac_clr <= '1';
                        if cnt_neur = N_OUT-1 then
                            cnt_neur <= (others => '0');
                            state    <= S_OUT;
                        else
                            cnt_neur <= cnt_neur + 1;
                            state    <= S_CALC;
                        end if;

                    when S_OUT =>
                        r_class  <= std_logic_vector(max_idx);
                        r_valid  <= '1';
                        r_done   <= '1';
                        state    <= S_DONE;

                    when S_DONE =>
                        r_done  <= '0';
                        r_valid <= '0';
                        if en = '0' then state <= S_LOAD; end if;

                    when others => state <= S_LOAD;
                end case;
            end if;
        end if;
    end process;

    class_out <= r_class;
    valid_out <= r_valid;
    done      <= r_done;

end architecture;