--  PBI bios rom emulation for the MiSTer Atari 800 core
--  Copyright (C) 2025 Wojciech Mostowski <wojciech.mostowski@gmail.com>
--
--  Based on cart_logic.vhd work by:
--  Copyright (C) 2011-2014 Matthias Reichl <hias@horus.com>
--
--  This program is free software; you can redistribute it and/or modify
--  it under the terms of the Lesser GNU General Public License as published by
--  the Free Software Foundation; either version 2 of the License, or
--  (at your option) any later version.
--
--  This program is distributed in the hope that it will be useful,
--  but WITHOUT ANY WARRANTY; without even the implied warranty of
--  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
--  GNU General Public License for more details.
--
--  You should have received a copy of the GNU General Public License
--  along with this program; if not, write to the Free Software
--  Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

library work;

-- Atari816: the one PBI device of the classic machine, the I/O processor's disk
-- (see core/README.md, "Fast disk"). Cut down from the MiSTer
-- original: no ROM banks and no scratch RAM at $D100 (254 registers there).
--   $D1FF write: bit 0 selects the device: its 2 KB ROM (SDRAM, written by the I/O processor)
--                replaces the math pack at $D800-$DFFF. The OS does this around each call.
--   $D1FE write: bit 0 = the request bit, read by the I/O processor: a request is pending
--                while it differs from the "served" byte the I/O processor keeps in the ROM.
--   $D1xx read:  $00 (no interrupt pending).
entity PBIROM is
	Port (
		clk: in std_logic;
		clk_enable: in std_logic;
		reset_n: in std_logic;
		a: in std_logic_vector (10 downto 0);
		rw: in std_logic;
		data_in: in std_logic_vector(7 downto 0);
		d1xx: in std_logic;
		d8xx: in std_logic;
		pbi_rom_address: out std_logic_vector(12 downto 0);
		pbi_rom_address_enable: out std_logic;
		data_out: out std_logic_vector(7 downto 0);
		cache_data_out: out std_logic_vector(7 downto 0);
		data_out_enable: out std_logic;
		req: out std_logic
	);
end PBIROM;

architecture vhdl of PBIROM is

signal pbi_rom_enable_reg: std_logic := '0';
signal req_reg: std_logic := '0';

begin

pbi_rom_address <= "00" & a(10 downto 0);
pbi_rom_address_enable <= d8xx and rw and pbi_rom_enable_reg;
data_out <= x"00";
cache_data_out <= x"00";
data_out_enable <= d1xx and rw;
req <= req_reg;

process(clk, reset_n)
begin
	if reset_n = '0' then
		pbi_rom_enable_reg <= '0';
		req_reg <= '0';
	elsif rising_edge(clk) then
		if (d1xx = '1') and (rw = '0') then
			if a(7 downto 0) = x"FF" then
				pbi_rom_enable_reg <= data_in(0);
			elsif a(7 downto 0) = x"FE" then
				req_reg <= data_in(0);
			end if;
		end if;
	end if;
end process;

end vhdl;
