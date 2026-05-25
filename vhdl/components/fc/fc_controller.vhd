library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fc_controller is
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
end entity;

architecture rtl of fc_controller is
    type t_state is (S_LOAD, S_CALC, S_FLUSH, S_BIAS, S_OUT, S_DONE);
    signal state : t_state := S_LOAD;
    signal flush_cnt : unsigned(1 downto 0) := (others => '0');
begin

    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                state <= S_LOAD;
                flush_cnt <= (others => '0');
            else
                case state is
                    when S_LOAD =>
                        if en = '1' and valid_in = '1' then
                            if cnt_in_done = '1' then
                                state <= S_CALC;
                            end if;
                        end if;

                    when S_CALC =>
                        if cnt_weight_done = '1' then
                            flush_cnt <= (others => '0');
                            state     <= S_FLUSH;
                        end if;

                    when S_FLUSH =>
                        flush_cnt <= flush_cnt + 1;
                        if flush_cnt = 2 then
                            state <= S_BIAS;
                        end if;

                    when S_BIAS =>
                        state <= S_OUT;

                    when S_OUT =>
                        if cnt_neur_done = '1' then
                            state <= S_DONE;
                        else
                            state <= S_CALC;
                        end if;

                    when S_DONE =>
                        if en = '0' then
                            state <= S_LOAD;
                        end if;
                    when others => state <= S_LOAD;
                end case;
            end if;
        end if;
    end process;

    -- Lógica de salidas basada en el estado actual (Combinacional)
    act_wr       <= '1' when (state = S_LOAD and en = '1' and valid_in = '1') else '0';
    act_addr_sel <= '1' when (state = S_CALC) else '0';
    cnt_in_en    <= '1' when (state = S_LOAD and en = '1' and valid_in = '1') else '0';
    cnt_weight_en<= '1' when (state = S_CALC) else '0';
    cnt_neur_en  <= '1' when (state = S_OUT) else '0';
    mac_en       <= '1' when (state = S_CALC) else '0';
    mac_clr      <= '1' when (state = S_LOAD and cnt_in_done = '1') or (state = S_OUT) else '0';
    out_valid    <= '1' when (state = S_OUT) else '0';
    layer_done   <= '1' when (state = S_DONE) else '0';

end architecture;