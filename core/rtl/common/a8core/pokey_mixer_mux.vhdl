---------------------------------------------------------------------------
-- (c) 2014 mark watson
-- I am happy for anyone to use this for non-commercial use.
-- If my vhdl files are used commercially or otherwise sold,
-- please contact me for explicit permission at scrameta (gmail).
-- This applies for source and binary form and derived works.
---------------------------------------------------------------------------
LIBRARY ieee;
USE ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use IEEE.STD_LOGIC_MISC.all;

ENTITY pokey_mixer_mux IS
PORT 
( 
	CLK : IN STD_LOGIC;

	ENABLE_179 : IN STD_LOGIC;

	CHANNEL_L_0 : IN STD_LOGIC_VECTOR(3 downto 0);
	CHANNEL_L_1 : IN STD_LOGIC_VECTOR(3 downto 0);
	CHANNEL_L_2 : IN STD_LOGIC_VECTOR(3 downto 0);
	CHANNEL_L_3 : IN STD_LOGIC_VECTOR(3 downto 0);
	COVOX_CHANNEL_L_0 : IN STD_LOGIC_VECTOR(7 downto 0);
	COVOX_CHANNEL_L_1 : IN STD_LOGIC_VECTOR(7 downto 0);

	CHANNEL_R_0 : IN STD_LOGIC_VECTOR(3 downto 0);
	CHANNEL_R_1 : IN STD_LOGIC_VECTOR(3 downto 0);
	CHANNEL_R_2 : IN STD_LOGIC_VECTOR(3 downto 0);
	CHANNEL_R_3 : IN STD_LOGIC_VECTOR(3 downto 0);
	COVOX_CHANNEL_R_0 : IN STD_LOGIC_VECTOR(7 downto 0);
	COVOX_CHANNEL_R_1 : IN STD_LOGIC_VECTOR(7 downto 0);
	
	GTIA_SOUND : IN STD_LOGIC;
	SIO_AUDIO : IN STD_LOGIC_VECTOR(7 downto 0);
	
	VOLUME_OUT_L : OUT STD_LOGIC_vector(15 downto 0);
	VOLUME_OUT_R : OUT STD_LOGIC_vector(15 downto 0)
);
END pokey_mixer_mux;

ARCHITECTURE vhdl OF pokey_mixer_mux IS
	signal VOLUME_OUT_NEXT : STD_LOGIC_VECTOR(15 downto 0);
	signal VOLUME_OUT_L_REG : STD_LOGIC_VECTOR(15 downto 0);
	signal VOLUME_POSTLOWPASS_L_REG : STD_LOGIC_VECTOR(15 downto 0);
BEGIN

-- Atari816 REV $0C: mono mixer (one POKEY: no right filter, no left/right multiplexing).
process(clk)
begin
	if (clk'event and clk='1') then
		VOLUME_OUT_L_REG <= VOLUME_OUT_NEXT;
	END IF;
END PROCESS;

shared_pokey_mixer : entity work.pokey_mixer
	port map
	(
		CLK => CLK,

		CHANNEL_0 => CHANNEL_L_0,
		CHANNEL_1 => CHANNEL_L_1,
		CHANNEL_2 => CHANNEL_L_2,
		CHANNEL_3 => CHANNEL_L_3,

		COVOX_CHANNEL_0 => COVOX_CHANNEL_L_0,
		COVOX_CHANNEL_1 => COVOX_CHANNEL_L_1,

		GTIA_SOUND => GTIA_SOUND,
		SIO_AUDIO => SIO_AUDIO,

		VOLUME_OUT_NEXT => VOLUME_OUT_NEXT
	);

filter_left : entity work.simple_low_pass_filter
	port map
	(
		CLK => CLK,
		AUDIO_IN => VOLUME_OUT_L_REG,
		SAMPLE_IN => ENABLE_179,
		AUDIO_OUT => VOLUME_POSTLOWPASS_L_REG
	);

	VOLUME_OUT_L <= VOLUME_POSTLOWPASS_L_REG;
	VOLUME_OUT_R <= VOLUME_POSTLOWPASS_L_REG;

END vhdl;

