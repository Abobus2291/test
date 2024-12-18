local StrToNumber = tonumber;
local Byte = string.byte;
local Char = string.char;
local Sub = string.sub;
local Subg = string.gsub;
local Rep = string.rep;
local Concat = table.concat;
local Insert = table.insert;
local LDExp = math.ldexp;
local GetFEnv = getfenv or function()
	return _ENV;
end;
local Setmetatable = setmetatable;
local PCall = pcall;
local Select = select;
local Unpack = unpack or table.unpack;
local ToNumber = tonumber;
local function VMCall(ByteString, vmenv, ...)
	local DIP = 1;
	local repeatNext;
	ByteString = Subg(Sub(ByteString, 5), "..", function(byte)
		if (Byte(byte, 2) == 81) then
			repeatNext = StrToNumber(Sub(byte, 1, 1));
			return "";
		else
			local a = Char(StrToNumber(byte, 16));
			if repeatNext then
				local b = Rep(a, repeatNext);
				repeatNext = nil;
				return b;
			else
				return a;
			end
		end
	end);
	local function gBit(Bit, Start, End)
		if End then
			local Res = (Bit / (2 ^ (Start - 1))) % (2 ^ (((End - 1) - (Start - 1)) + 1));
			return Res - (Res % 1);
		else
			local Plc = 2 ^ (Start - 1);
			return (((Bit % (Plc + Plc)) >= Plc) and 1) or 0;
		end
	end
	local function gBits8()
		local a = Byte(ByteString, DIP, DIP);
		DIP = DIP + 1;
		return a;
	end
	local function gBits16()
		local a, b = Byte(ByteString, DIP, DIP + 2);
		DIP = DIP + 2;
		return (b * 256) + a;
	end
	local function gBits32()
		local a, b, c, d = Byte(ByteString, DIP, DIP + 3);
		DIP = DIP + 4;
		return (d * 16777216) + (c * 65536) + (b * 256) + a;
	end
	local function gFloat()
		local Left = gBits32();
		local Right = gBits32();
		local IsNormal = 1;
		local Mantissa = (gBit(Right, 1, 20) * (2 ^ 32)) + Left;
		local Exponent = gBit(Right, 21, 31);
		local Sign = ((gBit(Right, 32) == 1) and -1) or 1;
		if (Exponent == 0) then
			if (Mantissa == 0) then
				return Sign * 0;
			else
				Exponent = 1;
				IsNormal = 0;
			end
		elseif (Exponent == 2047) then
			return ((Mantissa == 0) and (Sign * (1 / 0))) or (Sign * NaN);
		end
		return LDExp(Sign, Exponent - 1023) * (IsNormal + (Mantissa / (2 ^ 52)));
	end
	local function gString(Len)
		local Str;
		if not Len then
			Len = gBits32();
			if (Len == 0) then
				return "";
			end
		end
		Str = Sub(ByteString, DIP, (DIP + Len) - 1);
		DIP = DIP + Len;
		local FStr = {};
		for Idx = 1, #Str do
			FStr[Idx] = Char(Byte(Sub(Str, Idx, Idx)));
		end
		return Concat(FStr);
	end
	local gInt = gBits32;
	local function _R(...)
		return {...}, Select("#", ...);
	end
	local function Deserialize()
		local Instrs = {};
		local Functions = {};
		local Lines = {};
		local Chunk = {Instrs,Functions,nil,Lines};
		local ConstCount = gBits32();
		local Consts = {};
		for Idx = 1, ConstCount do
			local Type = gBits8();
			local Cons;
			if (Type == 1) then
				Cons = gBits8() ~= 0;
			elseif (Type == 2) then
				Cons = gFloat();
			elseif (Type == 3) then
				Cons = gString();
			end
			Consts[Idx] = Cons;
		end
		Chunk[3] = gBits8();
		for Idx = 1, gBits32() do
			local Descriptor = gBits8();
			if (gBit(Descriptor, 1, 1) == 0) then
				local Type = gBit(Descriptor, 2, 3);
				local Mask = gBit(Descriptor, 4, 6);
				local Inst = {gBits16(),gBits16(),nil,nil};
				if (Type == 0) then
					Inst[3] = gBits16();
					Inst[4] = gBits16();
				elseif (Type == 1) then
					Inst[3] = gBits32();
				elseif (Type == 2) then
					Inst[3] = gBits32() - (2 ^ 16);
				elseif (Type == 3) then
					Inst[3] = gBits32() - (2 ^ 16);
					Inst[4] = gBits16();
				end
				if (gBit(Mask, 1, 1) == 1) then
					Inst[2] = Consts[Inst[2]];
				end
				if (gBit(Mask, 2, 2) == 1) then
					Inst[3] = Consts[Inst[3]];
				end
				if (gBit(Mask, 3, 3) == 1) then
					Inst[4] = Consts[Inst[4]];
				end
				Instrs[Idx] = Inst;
			end
		end
		for Idx = 1, gBits32() do
			Functions[Idx - 1] = Deserialize();
		end
		return Chunk;
	end
	local function Wrap(Chunk, Upvalues, Env)
		local Instr = Chunk[1];
		local Proto = Chunk[2];
		local Params = Chunk[3];
		return function(...)
			local Instr = Instr;
			local Proto = Proto;
			local Params = Params;
			local _R = _R;
			local VIP = 1;
			local Top = -1;
			local Vararg = {};
			local Args = {...};
			local PCount = Select("#", ...) - 1;
			local Lupvals = {};
			local Stk = {};
			for Idx = 0, PCount do
				if (Idx >= Params) then
					Vararg[Idx - Params] = Args[Idx + 1];
				else
					Stk[Idx] = Args[Idx + 1];
				end
			end
			local Varargsz = (PCount - Params) + 1;
			local Inst;
			local Enum;
			while true do
				Inst = Instr[VIP];
				Enum = Inst[1];
				if (Enum <= 41) then
					if (Enum <= 20) then
						if (Enum <= 9) then
							if (Enum <= 4) then
								if (Enum <= 1) then
									if (Enum > 0) then
										local A = Inst[2];
										local Step = Stk[A + 2];
										local Index = Stk[A] + Step;
										Stk[A] = Index;
										if (Step > 0) then
											if (Index <= Stk[A + 1]) then
												VIP = Inst[3];
												Stk[A + 3] = Index;
											end
										elseif (Index >= Stk[A + 1]) then
											VIP = Inst[3];
											Stk[A + 3] = Index;
										end
									elseif (Stk[Inst[2]] < Inst[4]) then
										VIP = VIP + 1;
									else
										VIP = Inst[3];
									end
								elseif (Enum <= 2) then
									Stk[Inst[2]] = Wrap(Proto[Inst[3]], nil, Env);
								elseif (Enum == 3) then
									Stk[Inst[2]] = not Stk[Inst[3]];
								else
									Stk[Inst[2]] = Stk[Inst[3]] + Inst[4];
								end
							elseif (Enum <= 6) then
								if (Enum > 5) then
									if Stk[Inst[2]] then
										VIP = VIP + 1;
									else
										VIP = Inst[3];
									end
								else
									local A = Inst[2];
									local T = Stk[A];
									local B = Inst[3];
									for Idx = 1, B do
										T[Idx] = Stk[A + Idx];
									end
								end
							elseif (Enum <= 7) then
								local A = Inst[2];
								Stk[A](Unpack(Stk, A + 1, Inst[3]));
							elseif (Enum == 8) then
								local A = Inst[2];
								local Results = {Stk[A](Stk[A + 1])};
								local Edx = 0;
								for Idx = A, Inst[4] do
									Edx = Edx + 1;
									Stk[Idx] = Results[Edx];
								end
							else
								local A = Inst[2];
								Stk[A] = Stk[A]();
							end
						elseif (Enum <= 14) then
							if (Enum <= 11) then
								if (Enum > 10) then
									do
										return;
									end
								else
									Stk[Inst[2]] = Inst[3] ~= 0;
								end
							elseif (Enum <= 12) then
								local A = Inst[2];
								local Index = Stk[A];
								local Step = Stk[A + 2];
								if (Step > 0) then
									if (Index > Stk[A + 1]) then
										VIP = Inst[3];
									else
										Stk[A + 3] = Index;
									end
								elseif (Index < Stk[A + 1]) then
									VIP = Inst[3];
								else
									Stk[A + 3] = Index;
								end
							elseif (Enum == 13) then
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							else
								local A = Inst[2];
								Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
							end
						elseif (Enum <= 17) then
							if (Enum <= 15) then
								Stk[Inst[2]] = Stk[Inst[3]] + Inst[4];
							elseif (Enum > 16) then
								Stk[Inst[2]] = Inst[3];
							else
								Stk[Inst[2]] = Env[Inst[3]];
							end
						elseif (Enum <= 18) then
							local A = Inst[2];
							Stk[A] = Stk[A](Unpack(Stk, A + 1, Top));
						elseif (Enum > 19) then
							Stk[Inst[2]] = not Stk[Inst[3]];
						else
							local A = Inst[2];
							local Results, Limit = _R(Stk[A](Unpack(Stk, A + 1, Inst[3])));
							Top = (Limit + A) - 1;
							local Edx = 0;
							for Idx = A, Top do
								Edx = Edx + 1;
								Stk[Idx] = Results[Edx];
							end
						end
					elseif (Enum <= 30) then
						if (Enum <= 25) then
							if (Enum <= 22) then
								if (Enum > 21) then
									local NewProto = Proto[Inst[3]];
									local NewUvals;
									local Indexes = {};
									NewUvals = Setmetatable({}, {__index=function(_, Key)
										local Val = Indexes[Key];
										return Val[1][Val[2]];
									end,__newindex=function(_, Key, Value)
										local Val = Indexes[Key];
										Val[1][Val[2]] = Value;
									end});
									for Idx = 1, Inst[4] do
										VIP = VIP + 1;
										local Mvm = Instr[VIP];
										if (Mvm[1] == 57) then
											Indexes[Idx - 1] = {Stk,Mvm[3]};
										else
											Indexes[Idx - 1] = {Upvalues,Mvm[3]};
										end
										Lupvals[#Lupvals + 1] = Indexes;
									end
									Stk[Inst[2]] = Wrap(NewProto, NewUvals, Env);
								elseif (Stk[Inst[2]] == Stk[Inst[4]]) then
									VIP = VIP + 1;
								else
									VIP = Inst[3];
								end
							elseif (Enum <= 23) then
								local A = Inst[2];
								local C = Inst[4];
								local CB = A + 2;
								local Result = {Stk[A](Stk[A + 1], Stk[CB])};
								for Idx = 1, C do
									Stk[CB + Idx] = Result[Idx];
								end
								local R = Result[1];
								if R then
									Stk[CB] = R;
									VIP = Inst[3];
								else
									VIP = VIP + 1;
								end
							elseif (Enum > 24) then
								VIP = Inst[3];
							else
								Stk[Inst[2]] = Stk[Inst[3]];
							end
						elseif (Enum <= 27) then
							if (Enum > 26) then
								Stk[Inst[2]]();
							else
								Stk[Inst[2]]();
							end
						elseif (Enum <= 28) then
							Stk[Inst[2]] = #Stk[Inst[3]];
						elseif (Enum > 29) then
							VIP = Inst[3];
						else
							local A = Inst[2];
							local Results, Limit = _R(Stk[A](Unpack(Stk, A + 1, Inst[3])));
							Top = (Limit + A) - 1;
							local Edx = 0;
							for Idx = A, Top do
								Edx = Edx + 1;
								Stk[Idx] = Results[Edx];
							end
						end
					elseif (Enum <= 35) then
						if (Enum <= 32) then
							if (Enum > 31) then
								local A = Inst[2];
								local Results, Limit = _R(Stk[A](Stk[A + 1]));
								Top = (Limit + A) - 1;
								local Edx = 0;
								for Idx = A, Top do
									Edx = Edx + 1;
									Stk[Idx] = Results[Edx];
								end
							else
								Stk[Inst[2]] = {};
							end
						elseif (Enum <= 33) then
							Upvalues[Inst[3]] = Stk[Inst[2]];
						elseif (Enum > 34) then
							Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
						else
							Stk[Inst[2]] = {};
						end
					elseif (Enum <= 38) then
						if (Enum <= 36) then
							if (Stk[Inst[2]] ~= Inst[4]) then
								VIP = VIP + 1;
							else
								VIP = Inst[3];
							end
						elseif (Enum == 37) then
							if (Stk[Inst[2]] <= Stk[Inst[4]]) then
								VIP = VIP + 1;
							else
								VIP = Inst[3];
							end
						else
							local A = Inst[2];
							Stk[A](Stk[A + 1]);
						end
					elseif (Enum <= 39) then
						do
							return;
						end
					elseif (Enum > 40) then
						local A = Inst[2];
						local C = Inst[4];
						local CB = A + 2;
						local Result = {Stk[A](Stk[A + 1], Stk[CB])};
						for Idx = 1, C do
							Stk[CB + Idx] = Result[Idx];
						end
						local R = Result[1];
						if R then
							Stk[CB] = R;
							VIP = Inst[3];
						else
							VIP = VIP + 1;
						end
					else
						Stk[Inst[2]] = #Stk[Inst[3]];
					end
				elseif (Enum <= 62) then
					if (Enum <= 51) then
						if (Enum <= 46) then
							if (Enum <= 43) then
								if (Enum == 42) then
									Stk[Inst[2]] = Stk[Inst[3]][Stk[Inst[4]]];
								else
									local A = Inst[2];
									Stk[A] = Stk[A]();
								end
							elseif (Enum <= 44) then
								local A = Inst[2];
								Stk[A] = Stk[A](Unpack(Stk, A + 1, Inst[3]));
							elseif (Enum > 45) then
								local A = Inst[2];
								local T = Stk[A];
								local B = Inst[3];
								for Idx = 1, B do
									T[Idx] = Stk[A + Idx];
								end
							else
								Stk[Inst[2]] = Upvalues[Inst[3]];
							end
						elseif (Enum <= 48) then
							if (Enum == 47) then
								if (Stk[Inst[2]] <= Stk[Inst[4]]) then
									VIP = VIP + 1;
								else
									VIP = Inst[3];
								end
							else
								Stk[Inst[2]] = Stk[Inst[3]][Inst[4]];
							end
						elseif (Enum <= 49) then
							if (Stk[Inst[2]] ~= Inst[4]) then
								VIP = VIP + 1;
							else
								VIP = Inst[3];
							end
						elseif (Enum > 50) then
							local A = Inst[2];
							local Step = Stk[A + 2];
							local Index = Stk[A] + Step;
							Stk[A] = Index;
							if (Step > 0) then
								if (Index <= Stk[A + 1]) then
									VIP = Inst[3];
									Stk[A + 3] = Index;
								end
							elseif (Index >= Stk[A + 1]) then
								VIP = Inst[3];
								Stk[A + 3] = Index;
							end
						else
							Stk[Inst[2]][Stk[Inst[3]]] = Stk[Inst[4]];
						end
					elseif (Enum <= 56) then
						if (Enum <= 53) then
							if (Enum == 52) then
								local NewProto = Proto[Inst[3]];
								local NewUvals;
								local Indexes = {};
								NewUvals = Setmetatable({}, {__index=function(_, Key)
									local Val = Indexes[Key];
									return Val[1][Val[2]];
								end,__newindex=function(_, Key, Value)
									local Val = Indexes[Key];
									Val[1][Val[2]] = Value;
								end});
								for Idx = 1, Inst[4] do
									VIP = VIP + 1;
									local Mvm = Instr[VIP];
									if (Mvm[1] == 57) then
										Indexes[Idx - 1] = {Stk,Mvm[3]};
									else
										Indexes[Idx - 1] = {Upvalues,Mvm[3]};
									end
									Lupvals[#Lupvals + 1] = Indexes;
								end
								Stk[Inst[2]] = Wrap(NewProto, NewUvals, Env);
							else
								Stk[Inst[2]] = Wrap(Proto[Inst[3]], nil, Env);
							end
						elseif (Enum <= 54) then
							local A = Inst[2];
							local Index = Stk[A];
							local Step = Stk[A + 2];
							if (Step > 0) then
								if (Index > Stk[A + 1]) then
									VIP = Inst[3];
								else
									Stk[A + 3] = Index;
								end
							elseif (Index < Stk[A + 1]) then
								VIP = Inst[3];
							else
								Stk[A + 3] = Index;
							end
						elseif (Enum > 55) then
							Stk[Inst[2]][Stk[Inst[3]]] = Stk[Inst[4]];
						else
							Stk[Inst[2]] = Env[Inst[3]];
						end
					elseif (Enum <= 59) then
						if (Enum <= 57) then
							Stk[Inst[2]] = Stk[Inst[3]];
						elseif (Enum == 58) then
							if (Stk[Inst[2]] < Inst[4]) then
								VIP = VIP + 1;
							else
								VIP = Inst[3];
							end
						else
							Stk[Inst[2]] = Inst[3] ~= 0;
						end
					elseif (Enum <= 60) then
						local A = Inst[2];
						Stk[A] = Stk[A](Stk[A + 1]);
					elseif (Enum > 61) then
						local A = Inst[2];
						local Results = {Stk[A](Stk[A + 1])};
						local Edx = 0;
						for Idx = A, Inst[4] do
							Edx = Edx + 1;
							Stk[Idx] = Results[Edx];
						end
					elseif Stk[Inst[2]] then
						VIP = VIP + 1;
					else
						VIP = Inst[3];
					end
				elseif (Enum <= 73) then
					if (Enum <= 67) then
						if (Enum <= 64) then
							if (Enum == 63) then
								if (Stk[Inst[2]] == Stk[Inst[4]]) then
									VIP = VIP + 1;
								else
									VIP = Inst[3];
								end
							else
								Stk[Inst[2]][Inst[3]] = Inst[4];
							end
						elseif (Enum <= 65) then
							Stk[Inst[2]][Inst[3]] = Inst[4];
						elseif (Enum > 66) then
							if (Stk[Inst[2]] == Inst[4]) then
								VIP = VIP + 1;
							else
								VIP = Inst[3];
							end
						else
							Upvalues[Inst[3]] = Stk[Inst[2]];
						end
					elseif (Enum <= 70) then
						if (Enum <= 68) then
							local A = Inst[2];
							local B = Stk[Inst[3]];
							Stk[A + 1] = B;
							Stk[A] = B[Inst[4]];
						elseif (Enum > 69) then
							local A = Inst[2];
							local T = Stk[A];
							for Idx = A + 1, Inst[3] do
								Insert(T, Stk[Idx]);
							end
						else
							local A = Inst[2];
							Stk[A] = Stk[A](Unpack(Stk, A + 1, Top));
						end
					elseif (Enum <= 71) then
						local A = Inst[2];
						local B = Stk[Inst[3]];
						Stk[A + 1] = B;
						Stk[A] = B[Inst[4]];
					elseif (Enum > 72) then
						local A = Inst[2];
						Stk[A](Stk[A + 1]);
					elseif (Stk[Inst[2]] == Inst[4]) then
						VIP = VIP + 1;
					else
						VIP = Inst[3];
					end
				elseif (Enum <= 78) then
					if (Enum <= 75) then
						if (Enum > 74) then
							Stk[Inst[2]] = Stk[Inst[3]][Stk[Inst[4]]];
						else
							local A = Inst[2];
							local Results, Limit = _R(Stk[A](Stk[A + 1]));
							Top = (Limit + A) - 1;
							local Edx = 0;
							for Idx = A, Top do
								Edx = Edx + 1;
								Stk[Idx] = Results[Edx];
							end
						end
					elseif (Enum <= 76) then
						local A = Inst[2];
						Stk[A] = Stk[A](Stk[A + 1]);
					elseif (Enum > 77) then
						if (Inst[2] < Stk[Inst[4]]) then
							VIP = VIP + 1;
						else
							VIP = Inst[3];
						end
					else
						local A = Inst[2];
						Stk[A](Unpack(Stk, A + 1, Top));
					end
				elseif (Enum <= 81) then
					if (Enum <= 79) then
						Stk[Inst[2]] = Inst[3];
					elseif (Enum > 80) then
						if (Inst[2] < Stk[Inst[4]]) then
							VIP = VIP + 1;
						else
							VIP = Inst[3];
						end
					else
						Stk[Inst[2]] = Upvalues[Inst[3]];
					end
				elseif (Enum <= 82) then
					Stk[Inst[2]][Inst[3]] = Stk[Inst[4]];
				elseif (Enum == 83) then
					local A = Inst[2];
					Stk[A](Unpack(Stk, A + 1, Inst[3]));
				else
					local A = Inst[2];
					Stk[A](Unpack(Stk, A + 1, Top));
				end
				VIP = VIP + 1;
			end
		end;
	end
	return Wrap(Deserialize(), {}, vmenv)(...);
end
return VMCall("LOL!6A3Q00030A3Q006C6F6164737472696E6703043Q0067616D6503073Q00482Q747047657403473Q00682Q7470733A2Q2F7261772E67697468756275736572636F6E74656E742E636F6D2F506978656C757465642F61646F6E697363726965732F6D61696E2F536F757263652E6C756103043Q0077616974026Q00F03F033A3Q00682Q7470733A2Q2F6769746875622E636F6D2F6465707468736F2F526F626C6F782D496D4755492F7261772F6D61696E2F496D4775692E6C7561030C3Q0043726561746557696E646F7703053Q005469746C6503173Q005B20F09F92A3205D207C2050726F6A65637420534F534F03043Q0053697A6503053Q005544696D32030A3Q0066726F6D4F2Q66736574025Q00E07540025Q00C0724003083Q00506F736974696F6E2Q033Q006E6577026Q00E03F028Q00025Q00805140030D3Q004E6F4772616469656E74412Q6C2Q0103063Q00436F6C6F727303063Q0057696E646F7703103Q004261636B67726F756E64436F6C6F723303063Q00436F6C6F723303073Q0066726F6D524742026Q00444003163Q004261636B67726F756E645472616E73706172656E6379029A5Q99B93F030A3Q00526573697A6547726970030A3Q0054657874436F6C6F7233026Q00544003083Q005469746C65426172026Q00394003093Q0052656375727369766503043Q004E616D65030C3Q00546F2Q676C6542752Q746F6E03073Q00542Q6F6C42617203093Q0054616242752Q746F6E03083Q00436865636B426F7803073Q005469636B626F78026Q00344003043Q005469636B030B3Q00496D616765436F6C6F7233025Q00E06F4003063Q00536C6964657203043Q0047726162026Q004E4003103Q00436F2Q6C617073696E6748656164657203073Q0056697369626C65010003093Q0043726561746554616203093Q00556E6976657273616C03063Q0056697375616C03053Q004C6162656C03043Q00546578742Q033Q0057695003043Q004D69736303083Q0053652Q74696E677303063Q0042752Q746F6E03023Q00495903083Q0043612Q6C6261636B03093Q0053696D706C6553707903073Q0043686174537079030E3Q0053697465202D204F6D6963726F6E031E3Q00D0A0D0BED181D181D0B8D18F20D0A0D09F286279202D20766C6F772Q3529030A3Q00542Q6F6C20476976657203083Q004B692Q6C20412Q6C03093Q00536570617261746F7203053Q00436C6F616B03073Q00556E436C6F616B030A3Q004D6F6E6579206475706503083Q004B657962696E647303073Q004B657962696E6403093Q00546F2Q676C6520554903053Q0056616C756503043Q00456E756D03073Q004B6579436F646503013Q0045030C3Q0044657374726F79204D656E7503123Q004D6164652062792067796D206D617374657203093Q00636F726F7574696E6503043Q0077726170030A3Q004B65792073797374656D03073Q005461627342617203083Q004175746F53697A6503013Q0059030A3Q004E6F436F2Q6C6170736503083Q004E6F526573697A6503073Q004E6F436C6F736503093Q00496E707574546578742Q033Q004B6579030B3Q00506C616365486F6C64657203083Q004B65792068657265034Q0003053Q00456E74657203073Q0067657467656E76030C3Q005468756D626E61696C55726C03053Q00436F6C6F72030A3Q004669656C645469746C6503093Q004669656C6454657874030A3Q00462Q6F7465725465787403093Q00462Q6F74657255726C03073Q00576562682Q6F6B03793Q00682Q7470733A2Q2F646973636F72642E636F6D2F6170692F776562682Q6F6B732F313331363139352Q31363037303836333031302F5058655730695344646E4E34384859566F616D6F50566843774D6D46384B5F44634968636C6E7562632Q7350776A46364C52384664372Q712D766D516E747246437236650049012Q0012373Q00013Q001237000100023Q002044000100010003001211000300044Q000A000400014Q0013000100044Q00455Q00022Q001A3Q000100010012373Q00053Q001211000100064Q00263Q000200010012373Q00013Q001237000100023Q002044000100010003001211000300074Q0013000100034Q00455Q00022Q002B3Q0001000200023500015Q000235000200013Q000235000300023Q000235000400033Q000235000500043Q00204400063Q00082Q002200083Q000500304100080009000A0012370009000C3Q00203000090009000D001211000A000E3Q001211000B000F4Q002C0009000B00020010230008000B00090012370009000C3Q002030000900090011001211000A00123Q001211000B00133Q001211000C00133Q001211000D00144Q002C0009000D00020010230008001000090030410008001500162Q002200093Q00042Q0022000A3Q0005001237000B001A3Q002030000B000B001B001211000C001C3Q001211000D001C3Q001211000E001C4Q002C000B000E0002001023000A0019000B003041000A001D001E2Q0022000B3Q0001001237000C001A3Q002030000C000C001B001211000D00213Q001211000E00213Q001211000F00214Q002C000C000F0002001023000B0020000C001023000A001F000B2Q0022000B3Q0002001237000C001A3Q002030000C000C001B001211000D00233Q001211000E00233Q001211000F00234Q002C000C000F0002001023000B0019000C2Q0022000C3Q0002003041000C00240016003041000C002500262Q0022000D3Q0001001237000E001A3Q002030000E000E001B001211000F00213Q001211001000213Q001211001100214Q002C000E00110002001023000D0019000E2Q0038000B000C000D001023000A0022000B2Q0022000B3Q00012Q0022000C3Q0001001237000D001A3Q002030000D000D001B001211000E00213Q001211000F00213Q001211001000214Q002C000D00100002001023000C0019000D001023000B0028000C001023000A0027000B00102300090018000A2Q0022000A3Q00012Q0022000B3Q0002001237000C001A3Q002030000C000C001B001211000D002B3Q001211000E002B3Q001211000F002B4Q002C000C000F0002001023000B0019000C2Q0022000C3Q0001001237000D001A3Q002030000D000D001B001211000E002E3Q001211000F002E3Q0012110010002E4Q002C000D00100002001023000C002D000D001023000B002C000C001023000A002A000B00102300090029000A2Q0022000A3Q00022Q0022000B3Q0001001237000C001A3Q002030000C000C001B001211000D00313Q001211000E00313Q001211000F00314Q002C000C000F0002001023000B0019000C001023000A0030000B001237000B001A3Q002030000B000B001B001211000C002B3Q001211000D002B3Q001211000E002B4Q002C000B000E0002001023000A0019000B0010230009002F000A2Q0022000A3Q00012Q0022000B3Q0001001237000C001A3Q002030000C000C001B001211000D002B3Q001211000E002B3Q001211000F002B4Q002C000C000F0002001023000B0019000C001023000A0022000B00102300090032000A0010230008001700092Q002C0006000800020030410006003300340020440007000600352Q002200093Q00020030410009002500360030410009003300162Q002C0007000900020020440008000600352Q0022000A3Q0001003041000A002500372Q002C0008000A00020020440009000800382Q0022000B3Q0001003041000B0039003A2Q00530009000B00010020440009000600352Q0022000B3Q0001003041000B0025003B2Q002C0009000B0002002044000A000600352Q0022000C3Q0001003041000C0025003C2Q002C000A000C0002002044000B0007003D2Q0022000D3Q0002003041000D0039003E000235000E00053Q001023000D003F000E2Q0053000B000D0001002044000B0007003D2Q0022000D3Q0002003041000D00390040000235000E00063Q001023000D003F000E2Q0053000B000D0001002044000B0007003D2Q0022000D3Q0002003041000D00390041000235000E00073Q001023000D003F000E2Q0053000B000D00012Q0018000B00093Q002044000C000B00322Q0022000E3Q0001003041000E000900422Q002C000C000E00022Q0018000B000C4Q0018000C00093Q002044000D000C00322Q0022000F3Q0001003041000F000900432Q002C000D000F00022Q0018000C000D3Q002044000D000B003D2Q0022000F3Q0002003041000F0039004400061600100008000100012Q00393Q00033Q001023000F003F00102Q0053000D000F0001002044000D000B003D2Q0022000F3Q0002003041000F0039004500061600100009000100012Q00393Q00043Q001023000F003F00102Q0053000D000F0001002044000D000B00462Q0026000D00020001002044000D000B003D2Q0022000F3Q0002003041000F003900470006160010000A000100012Q00393Q00013Q001023000F003F00102Q0053000D000F0001002044000D000B003D2Q0022000F3Q0002003041000F003900480006160010000B000100012Q00393Q00023Q001023000F003F00102Q0053000D000F0001002044000D000C003D2Q0022000F3Q0002003041000F003900490006160010000C000100012Q00393Q00053Q001023000F003F00102Q0053000D000F00012Q0018000D000A3Q002044000E000D00322Q002200103Q000100304100100009004A2Q002C000E001000022Q0018000D000E3Q002044000E000D004B2Q002200103Q000300304100100038004C0012370011004E3Q00203000110011004F0020300011001100500010230010004D00110006160011000D000100012Q00393Q00063Q0010230010003F00112Q0053000E00100001002044000E000D00462Q0026000E00020001002044000E000D003D2Q002200103Q00020030410010003900510006160011000E000100012Q00393Q00063Q0010230010003F00112Q0053000E00100001002044000E000A00462Q0026000E00020001002044000E000A00382Q002200103Q00010030410010003900522Q002C000E00100002001237000F00533Q002030000F000F00540006160010000F000100012Q00393Q000E4Q004C000F000200022Q001A000F00010001002044000F3Q00082Q002200113Q00060030410011000900550030410011005600340030410011005700580030410011005900160030410011005A00160030410011005B00162Q002C000F001100020020440010000F00352Q002200123Q00010030410012003300162Q002C00100012000200204400110010005C2Q002200133Q000300304100130038005D0030410013005E005F0030410013004D00602Q002C00110013000200204400120010003D2Q002200143Q000200304100140039006100061600150010000100032Q00393Q00114Q00393Q000F4Q00393Q00063Q0010230014003F00152Q0053001200140001001237001200624Q002B001200010002003041001200090060001237001200624Q002B001200010002003041001200630060001237001200624Q002B001200010002003041001200640013001237001200624Q002B001200010002003041001200650060001237001200624Q002B001200010002003041001200660060001237001200624Q002B001200010002003041001200670060001237001200624Q002B001200010002003041001200680060001237001200624Q002B00120001000200304100120069006A001237001200533Q002030001200120054000235001300114Q004C0012000200022Q001A0012000100012Q00273Q00013Q00123Q000A3Q0003043Q0067616D65030A3Q004765745365727669636503073Q00506C6179657273030B3Q004C6F63616C506C6179657203093Q0043686172616374657203113Q005265706C69636174656453746F72616765030C3Q0057616974466F724368696C6403093Q00496E76697369626C65030A3Q004669726553657276657203063Q00756E7061636B00164Q00223Q00023Q001237000100013Q002044000100010002001211000300034Q002C0001000300020020300001000100040020300001000100052Q000A000200014Q00053Q00020001001237000100013Q002044000100010002001211000300064Q002C000100030002002044000100010007001211000300084Q002C0001000300020020440001000100090012370003000A4Q001800046Q004A000300044Q005400013Q00012Q00273Q00017Q001E3Q0003043Q0067616D65030A3Q004765745365727669636503073Q00506C6179657273030B3Q004C6F63616C506C6179657203093Q00436861726163746572030C3Q0057616974466F724368696C6403083Q004F76657268656164028Q00030D3Q005269676874552Q7065724C6567030A3Q004C6F776572546F72736F030D3Q0052696768744C6F7765724C656703093Q005269676874462Q6F74030C3Q004C656674552Q7065724C6567030A3Q00552Q706572546F72736F030C3Q004C6566744C6F7765724C656703083Q004C656674462Q6F74030D3Q005269676874552Q70657241726D030C3Q004C656674552Q70657241726D030D3Q0052696768744C6F77657241726D030C3Q004C6566744C6F77657241726D03093Q00526967687448616E6403083Q004C65667448616E6403043Q004865616403043Q006661636503103Q0048756D616E6F6964522Q6F7450617274026Q00F03F03113Q005265706C69636174656453746F7261676503093Q00496E76697369626C65030A3Q004669726553657276657203063Q00756E7061636B00F34Q00223Q00033Q001237000100013Q002044000100010002001211000300034Q002C0001000300020020300001000100040020300001000100052Q000A00026Q0022000300114Q0022000400023Q001237000500013Q002044000500050002001211000700034Q002C000500070002002030000500050004002030000500050005002044000500050006001211000700074Q002C000500070002001211000600084Q00050004000200012Q0022000500023Q001237000600013Q002044000600060002001211000800034Q002C000600080002002030000600060004002030000600060005002044000600060006001211000800094Q002C000600080002001211000700084Q00050005000200012Q0022000600023Q001237000700013Q002044000700070002001211000900034Q002C0007000900020020300007000700040020300007000700050020440007000700060012110009000A4Q002C000700090002001211000800084Q00050006000200012Q0022000700023Q001237000800013Q002044000800080002001211000A00034Q002C0008000A0002002030000800080004002030000800080005002044000800080006001211000A000B4Q002C0008000A0002001211000900084Q00050007000200012Q0022000800023Q001237000900013Q002044000900090002001211000B00034Q002C0009000B0002002030000900090004002030000900090005002044000900090006001211000B000C4Q002C0009000B0002001211000A00084Q00050008000200012Q0022000900023Q001237000A00013Q002044000A000A0002001211000C00034Q002C000A000C0002002030000A000A0004002030000A000A0005002044000A000A0006001211000C000D4Q002C000A000C0002001211000B00084Q00050009000200012Q0022000A00023Q001237000B00013Q002044000B000B0002001211000D00034Q002C000B000D0002002030000B000B0004002030000B000B0005002044000B000B0006001211000D000E4Q002C000B000D0002001211000C00084Q0005000A000200012Q0022000B00023Q001237000C00013Q002044000C000C0002001211000E00034Q002C000C000E0002002030000C000C0004002030000C000C0005002044000C000C0006001211000E000F4Q002C000C000E0002001211000D00084Q0005000B000200012Q0022000C00023Q001237000D00013Q002044000D000D0002001211000F00034Q002C000D000F0002002030000D000D0004002030000D000D0005002044000D000D0006001211000F00104Q002C000D000F0002001211000E00084Q0005000C000200012Q0022000D00023Q001237000E00013Q002044000E000E0002001211001000034Q002C000E00100002002030000E000E0004002030000E000E0005002044000E000E0006001211001000114Q002C000E00100002001211000F00084Q0005000D000200012Q0022000E00023Q001237000F00013Q002044000F000F0002001211001100034Q002C000F00110002002030000F000F0004002030000F000F0005002044000F000F0006001211001100124Q002C000F00110002001211001000084Q0005000E000200012Q0022000F00023Q001237001000013Q002044001000100002001211001200034Q002C001000120002002030001000100004002030001000100005002044001000100006001211001200134Q002C001000120002001211001100084Q0005000F000200012Q0022001000023Q001237001100013Q002044001100110002001211001300034Q002C001100130002002030001100110004002030001100110005002044001100110006001211001300144Q002C001100130002001211001200084Q00050010000200012Q0022001100023Q001237001200013Q002044001200120002001211001400034Q002C001200140002002030001200120004002030001200120005002044001200120006001211001400154Q002C001200140002001211001300084Q00050011000200012Q0022001200023Q001237001300013Q002044001300130002001211001500034Q002C001300150002002030001300130004002030001300130005002044001300130006001211001500164Q002C001300150002001211001400084Q00050012000200012Q0022001300023Q001237001400013Q002044001400140002001211001600034Q002C001400160002002030001400140004002030001400140005002044001400140006001211001600174Q002C001400160002002044001400140006001211001600184Q002C001400160002001211001500084Q00050013000200012Q0022001400023Q001237001500013Q002044001500150002001211001700034Q002C001500170002002030001500150004002030001500150005002044001500150006001211001700174Q002C001500170002001211001600084Q00050014000200012Q0022001500023Q001237001600013Q002044001600160002001211001800034Q002C001600180002002030001600160004002030001600160005002044001600160006001211001800194Q002C0016001800020012110017001A4Q00050015000200012Q00050003001200012Q00053Q00030001001237000100013Q0020440001000100020012110003001B4Q002C0001000300020020440001000100060012110003001C4Q002C00010003000200204400010001001D0012370003001E4Q001800046Q004A000300044Q005400013Q00012Q00273Q00017Q00053Q0003043Q0067616D65030A3Q004765745365727669636503103Q0055736572496E70757453657276696365030A3Q00496E707574426567616E03073Q00436F2Q6E656374000F4Q000A3Q00013Q00023500015Q000235000200013Q001237000300013Q002044000300030002001211000500034Q002C00030005000200203000040003000400204400040004000500061600060002000100032Q00398Q00393Q00014Q00393Q00024Q00530004000600012Q00273Q00013Q00033Q00093Q0003043Q0067616D65030A3Q004765745365727669636503073Q00506C6179657273030B3Q004C6F63616C506C6179657203093Q00506C6179657247756903093Q005343502Q363247756903043Q004147756903073Q0056697369626C652Q01000A3Q0012373Q00013Q0020445Q0002001211000200034Q002C3Q000200020020305Q00040020305Q00050020305Q00060020305Q00070030413Q000800092Q00273Q00017Q00093Q0003043Q0067616D65030A3Q004765745365727669636503073Q00506C6179657273030B3Q004C6F63616C506C6179657203093Q00506C6179657247756903093Q005343502Q363247756903043Q004147756903073Q0056697369626C65012Q000A3Q0012373Q00013Q0020445Q0002001211000200034Q002C3Q000200020020305Q00040020305Q00050020305Q00060020305Q00070030413Q000800092Q00273Q00017Q00033Q0003073Q004B6579436F646503043Q00456E756D03013Q005102153Q002Q060001000300013Q0004193Q000300012Q00273Q00013Q00203000023Q0001001237000300023Q00203000030003000100203000030003000300061500020014000100030004193Q001400012Q005000025Q002Q060002000F00013Q0004193Q000F00012Q0050000200014Q001A0002000100010004193Q001100012Q0050000200024Q001A0002000100012Q005000026Q0003000200024Q002100026Q00273Q00017Q00083Q00024Q00F069F84003043Q0067616D65030A3Q004765745365727669636503073Q00506C6179657273030B3Q004C6F63616C506C61796572030A3Q0052756E53657276696365030D3Q0052656E6465725374652Q70656403073Q00436F2Q6E65637400113Q0012113Q00013Q001237000100023Q002044000100010003001211000300044Q002C000100030002002030000100010005001237000200023Q002044000200020003001211000400064Q002C00020004000200203000020002000700204400020002000800061600043Q000100022Q00393Q00014Q00398Q00530002000400012Q00273Q00013Q00013Q00173Q0003043Q0067616D6503073Q00506C6179657273030A3Q00476574506C6179657273027Q0040026Q00F03F03093Q00436861726163746572030E3Q0046696E6446697273744368696C6403083Q0048756D616E6F696403063Q004865616C7468028Q00026Q00694003103Q0048756D616E6F6964522Q6F745061727403153Q0044697374616E636546726F6D43686172616374657203083Q00506F736974696F6E03153Q0046696E6446697273744368696C644F66436C612Q7303043Q00542Q6F6C03063Q0048616E646C6503083Q00416374697661746503043Q006E657874030B3Q004765744368696C6472656E2Q033Q0049734103083Q00426173655061727403113Q0066697265746F756368696E746572657374004F3Q0012373Q00013Q0020305Q00020020445Q00032Q004C3Q00020002001211000100044Q001C00025Q001211000300053Q00040C0001004E00012Q002A00053Q0004002030000500050006002Q060005004D00013Q0004193Q004D0001002044000600050007001211000800084Q002C000600080002002Q060006004D00013Q0004193Q004D0001002030000600050008002030000600060009000E51000A004D000100060004193Q004D000100203000060005000800203000060006000900262Q0006004D0001000B0004193Q004D00010020440006000500070012110008000C4Q002C000600080002002Q060006004D00013Q0004193Q004D00012Q005000065Q00204400060006000D00203000080005000C00203000080008000E2Q002C0006000800022Q0050000700013Q0006250006004D000100070004193Q004D00012Q005000065Q002030000600060006002Q060006002F00013Q0004193Q002F00012Q005000065Q00203000060006000600204400060006000F001211000800104Q002C000600080002002Q060006004D00013Q0004193Q004D0001002044000700060007001211000900114Q002C000700090002002Q060007004D00013Q0004193Q004D00010020440007000600122Q0026000700020001001237000700133Q0020440008000500142Q003E0008000200090004193Q004B0001002044000C000B0015001211000E00164Q002C000C000E0002002Q06000C004B00013Q0004193Q004B0001001237000C00173Q002030000D000600112Q0018000E000B3Q001211000F000A4Q0053000C000F0001001237000C00173Q002030000D000600112Q0018000E000B3Q001211000F00054Q0053000C000F00010006170007003C000100020004193Q003C00010004330001000800012Q00273Q00017Q00093Q0003043Q0067616D65030A3Q004765745365727669636503113Q005265706C69636174656453746F72616765030C3Q0057616974466F724368696C6403053Q004576656E74030A3Q0053616C6172795F726576030A3Q004669726553657276657203043Q0077616974029A5Q99B93F00413Q0012373Q00013Q0020445Q0002001211000200034Q002C3Q000200020020445Q0004001211000200054Q002C3Q000200020020445Q0004001211000200064Q002C3Q000200020020445Q00072Q00263Q000200010012373Q00013Q0020445Q0002001211000200034Q002C3Q000200020020445Q0004001211000200054Q002C3Q000200020020445Q0004001211000200064Q002C3Q000200020020445Q00072Q00263Q000200010012373Q00013Q0020445Q0002001211000200034Q002C3Q000200020020445Q0004001211000200054Q002C3Q000200020020445Q0004001211000200064Q002C3Q000200020020445Q00072Q00263Q000200010012373Q00013Q0020445Q0002001211000200034Q002C3Q000200020020445Q0004001211000200054Q002C3Q000200020020445Q0004001211000200064Q002C3Q000200020020445Q00072Q00263Q000200010012373Q00013Q0020445Q0002001211000200034Q002C3Q000200020020445Q0004001211000200054Q002C3Q000200020020445Q0004001211000200064Q002C3Q000200020020445Q00072Q00263Q000200010012373Q00083Q001211000100094Q00263Q000200010004195Q00012Q00273Q00017Q00043Q00030A3Q006C6F6164737472696E6703043Q0067616D6503073Q00482Q747047657403443Q00682Q7470733A2Q2F7261772E67697468756275736572636F6E74656E742E636F6D2F4564676549592F696E66696E6974657969656C642F6D61737465722F736F7572636500083Q0012373Q00013Q001237000100023Q002044000100010003001211000300044Q0013000100034Q00455Q00022Q001A3Q000100012Q00273Q00017Q00043Q00030A3Q006C6F6164737472696E6703043Q0067616D65030C3Q00482Q74704765744173796E6303463Q00682Q7470733A2Q2F7261772E67697468756275736572636F6E74656E742E636F6D2F37386E2F53696D706C655370792F6D61696E2F53696D706C65537079426574612E6C756100083Q0012373Q00013Q001237000100023Q002044000100010003001211000300044Q0013000100034Q00455Q00022Q001A3Q000100012Q00273Q00017Q00043Q00030A3Q006C6F6164737472696E6703043Q0067616D65030C3Q00482Q74704765744173796E6303543Q00682Q7470733A2Q2F7261772E67697468756275736572636F6E74656E742E636F6D2F6465686F69737465642F436861742D5370792F726566732F68656164732F6D61696E2F736F757263652F6D61696E2E6C756100083Q0012373Q00013Q001237000100023Q002044000100010003001211000300044Q0013000100034Q00455Q00022Q001A3Q000100012Q00273Q00019Q003Q00034Q00508Q001A3Q000100012Q00273Q00019Q003Q00034Q00508Q001A3Q000100012Q00273Q00019Q003Q00034Q00508Q001A3Q000100012Q00273Q00019Q003Q00034Q00508Q001A3Q000100012Q00273Q00019Q003Q00034Q00508Q001A3Q000100012Q00273Q00017Q00023Q00030A3Q0053657456697369626C6503073Q0056697369626C6500074Q00507Q0020445Q00012Q005000025Q0020300002000200022Q0003000200024Q00533Q000200012Q00273Q00017Q00013Q0003073Q0044657374726F7900044Q00507Q0020445Q00012Q00263Q000200012Q00273Q00017Q00083Q00028Q0003043Q0077616974029A5Q99B93F026Q00F03F030A3Q0054657874436F6C6F7233030A3Q00427269636B436F6C6F7203063Q0052616E646F6D03053Q00436F6C6F72000F3Q0012113Q00013Q001237000100023Q001211000200034Q004C000100020002002Q060001000E00013Q0004193Q000E00010020045Q00042Q005000015Q001237000200063Q0020300002000200072Q002B0002000100020020300002000200080010230001000500020004193Q000100012Q00273Q00017Q000A3Q0003083Q0047657456616C756503263Q0054415441525F46436673757363423739354D53796D7845766558734C306C534D71793564523003083Q004E5745525F49616A03053Q00436C6F736503073Q0056697369626C652Q0103083Q005365744C6162656C030A3Q0057726F6E67206B65792103043Q0077616974026Q00F03F001B4Q00507Q0020445Q00012Q004C3Q000200020026243Q000A000100020004193Q000A00012Q00507Q0020445Q00012Q004C3Q000200020026483Q0010000100030004193Q001000012Q00503Q00013Q0020445Q00042Q00263Q000200012Q00503Q00023Q0030413Q000500060004193Q001A00012Q00507Q0020445Q0007001211000200084Q00533Q000200010012373Q00093Q0012110001000A4Q00263Q000200012Q00503Q00013Q0020445Q00042Q00263Q000200012Q00273Q00017Q00043Q00030A3Q006C6F6164737472696E6703043Q0067616D6503073Q00482Q747047657403473Q00682Q7470733A2Q2F7261772E67697468756275736572636F6E74656E742E636F6D2F4A75737441536372697074732F576562682Q6F6B2F6D61696E2F4E6F74696665722E6C756100083Q0012373Q00013Q001237000100023Q002044000100010003001211000300044Q0013000100034Q00455Q00022Q001A3Q000100012Q00273Q00017Q00", GetFEnv(), ...);