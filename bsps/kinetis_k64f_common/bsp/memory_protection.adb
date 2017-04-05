--
--  Copyright (c) 2016, German Rivera
--  All rights reserved.
--
--  Redistribution and use in source and binary forms, with or without
--  modification, are permitted provided that the following conditions are met:
--
--  * Redistributions of source code must retain the above copyright notice,
--    this list of conditions and the following disclaimer.
--
--  * Redistributions in binary form must reproduce the above copyright notice,
--    this list of conditions and the following disclaimer in the documentation
--    and/or other materials provided with the distribution.
--
--  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
--  AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
--  IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
--  ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
--  LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
--  CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
--  SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
--  INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
--  CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
--  ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
--  POSSIBILITY OF SUCH DAMAGE.
--

with System.BB.Parameters;
with Interfaces.Bit_Types;
with System.Machine_Code;

package body Memory_Protection is
   use Interfaces.Bit_Types;
   use Interfaces;

   pragma Compile_Time_Error (
      MPU_Region_Index_Type'Enum_Rep (MPU_Region_Index_Type'First) <
      Kinetis_K64F.MPU.Region_Index_Type'First
      or
      MPU_Region_Index_Type'Enum_Rep (MPU_Region_Index_Type'Last) >
      Kinetis_K64F.MPU.Region_Index_Type'Last,
      "MPU_Region_Index_Type contains invalid region numbers");

   procedure Define_Mpu_Region (
      MPU_Region_Index : MPU_Region_Index_Type;
      Bus_Master : Bus_Master_Type;
      First_Address : System.Address;
      Last_Address : System.Address;
      Type1_Permissions : Bus_Master_Permissions_Type1;
      Type2_Permissions : Bus_Master_Permissions_Type2)
      with Pre => MPU_Region_Index >= Global_Unprivileged_Code_Region;
   --
   --  Configure an MPU region to cover a given range of addresses and with
   --  the given access permissions, for the givenbus master.
   --

   Num_Mpu_Regions_Table : constant array (0 .. 2) of Natural :=
      (0 => 8,
       1 => 12,
       2 => 16);

   type Memory_Protection_Type is record
      Initialized : Boolean := False;
      Num_Regions : Natural := 0;
   end record;

   Memory_Protection_Var : Memory_Protection_Type;

   --
   --  Linker-script symbols defined in
   --  embedded-runtimes/bsps/kinetis_k64f_common/bsp/common-ROM.ld
   --

   --  Start address of the text section in flash
   Flash_Text_Start : constant Unsigned_32;
   pragma Import (Asm, Flash_Text_Start, "__flash_text_start");

   --  End address of the text section in flash
   --  Flash_Text_End : constant Unsigned_32;
   --  pragma Import (Asm, Flash_Text_End, "__flash_text_end");

   --  End address of the rodata section in flash
   Rom_End : constant Unsigned_32;
   pragma Import (Asm, Rom_End, "__rom_end");

   --  Start address of the main stack (stack for ISRs)
   --  Main_Stack_Start : constant Unsigned_32;
   --  pragma Import (Asm, Main_Stack_Start, "__stack_start");

   --  Start address of the main stack (end for ISRs)
   --  Main_Stack_End : constant Unsigned_32;
   --  pragma Import (Asm, Main_Stack_End, "__stack_end");

   ----------------------------
   -- Define_DMA_Data_Region --
   ----------------------------

   procedure Define_DMA_Data_Region (Data_Region_Index : MPU_Region_Index_Type;
                                     DMA_Master : Bus_Master_Type;
                                     Start_Address : System.Address;
                                     Size_In_Bytes : Integer_Address;
                                     Is_Read_Only : Boolean := False)
   is
      Data_Region : constant Data_Region_Type :=
         (First_Address => Start_Address,
          Last_Address =>
             To_Address (To_Integer (Start_Address) + Size_In_Bytes - 1),
          Permissions => (if Is_Read_Only then Read_Only else Read_Write));
   begin
      Define_MPU_Data_Region (Data_Region_Index, DMA_Master, Data_Region);
   end Define_DMA_Data_Region;

   -----------------
   -- Disable_MPU --
   -----------------

   procedure Disable_MPU is
   begin
      MPU_Registers.CESR := (VLD => 0, others => <>);
   end Disable_MPU;

   -----------------------
   -- Define_Mpu_Region --
   -----------------------

   procedure Define_Mpu_Region (
      MPU_Region_Index : MPU_Region_Index_Type;
      Bus_Master : Bus_Master_Type;
      First_Address : System.Address;
      Last_Address : System.Address;
      Type1_Permissions : Bus_Master_Permissions_Type1;
      Type2_Permissions : Bus_Master_Permissions_Type2)
   is
      WORD2_Value : WORD2_Register_Type;
      Region_Index : constant Region_Index_Type := MPU_Region_Index'Enum_Rep;
   begin
      --
      --  Configure region:
      --
      --  NOTE: writing to registers WORD0, WORD1 and WORD2 of the region
      --  descriptor for region 'Region_Index' will disable access to
      --  the region (turn off bit MPU_WORD_VLD_MASK in register WORD3):
      --

      MPU_Registers.Region_Descriptors (Region_Index).WORD0 :=
         Unsigned_32 (To_Integer (First_Address));

      MPU_Registers.Region_Descriptors (Region_Index).WORD1 :=
          Unsigned_32 (To_Integer (Last_Address));

      WORD2_Value := MPU_Registers.Region_Descriptors (Region_Index).WORD2;

      case Bus_Master is
         when Cpu_Core0 =>
            WORD2_Value.Bus_Master_CPU_Core_Perms := Type1_Permissions;
         when Dma_Device_DMA_Engine =>
            WORD2_Value.Bus_Master_DMA_EZport_Perms := Type1_Permissions;
         when Dma_Device_ENET =>
            WORD2_Value.Bus_Master_ENET_Perms := Type1_Permissions;
         when Dma_Device_USB =>
            WORD2_Value.Bus_Master_USB_Perms := Type2_Permissions;
         when Dma_Device_SDHC =>
            WORD2_Value.Bus_Master_SDHC_Perms := Type2_Permissions;
         when Dma_Device_Master6 =>
            WORD2_Value.Bus_Master6_Perms := Type2_Permissions;
         when Dma_Device_Master7 =>
            WORD2_Value.Bus_Master7_Perms := Type2_Permissions;
         when others =>
            pragma Assert (False);
      end case;

      MPU_Registers.Region_Descriptors (Region_Index).WORD2 := WORD2_Value;

      --
      --  Re-enable access to the region:
      --
      MPU_Registers.Region_Descriptors (Region_Index).WORD3 :=
         (VLD => 1, others => <>);
   end Define_Mpu_Region;

   ----------------------------
   -- Define_MPU_Data_Region --
   ----------------------------

   procedure Define_MPU_Data_Region (
      Data_Region_Index : MPU_Region_Index_Type;
      Bus_Master : Bus_Master_Type;
      Data_Region : Data_Region_Type)
   is
      Type1_Read_Write_Permissions : constant Bus_Master_Permissions_Type1 :=
         (User_Mode_Permissions => (Execute_Allowed => 0,
                                    Write_Allowed => 1,
                                    Read_Allowed => 1),
          others => <>);

      Type1_Read_Only_Permissions : constant Bus_Master_Permissions_Type1 :=
         (User_Mode_Permissions => (Execute_Allowed => 0,
                                    Write_Allowed => 0,
                                    Read_Allowed => 1),
          others => <>);

      Type2_Read_Write_Permissions : constant Bus_Master_Permissions_Type2 :=
         (Write_Allowed => 1, Read_Allowed => 1);

      Type2_Read_Only_Permissions : constant Bus_Master_Permissions_Type2 :=
         (Write_Allowed => 0, Read_Allowed => 1);

      Type1_Permissions : Bus_Master_Permissions_Type1;
      Type2_Permissions : Bus_Master_Permissions_Type2;
   begin
      case Data_Region.Permissions is
         when Read_Only =>
            if Bus_Master <= Dma_Device_ENET then
               Type1_Permissions := Type1_Read_Only_Permissions;
            else
               Type2_Permissions := Type2_Read_Only_Permissions;
            end if;
         when Read_Write =>
            if Bus_Master <= Dma_Device_ENET then
               Type1_Permissions := Type1_Read_Write_Permissions;
            else
               Type2_Permissions := Type2_Read_Write_Permissions;
            end if;
         when others =>
            pragma Assert (False);
      end case;

      Define_Mpu_Region (
            Data_Region_Index,
            Bus_Master,
            Data_Region.First_Address,
            Data_Region.Last_Address,
            Type1_Permissions,
            Type2_Permissions);
   end Define_MPU_Data_Region;

   -------------------------------------------
   -- Enable_Peripheral_Unprivileged_Access --
   -------------------------------------------

   procedure Enable_Peripheral_Unprivileged_Access
   is
   begin
      null; --  ???
   end Enable_Peripheral_Unprivileged_Access;

   ---------------------------
   -- Enter_Privileged_Mode --
   ---------------------------

   function Enter_Privileged_Mode return Boolean
   is
   begin
      System.Machine_Code.Asm
        (Template =>
         --  Check if CPU is running in handler mode:
         "mrs  r0, ipsr" & ASCII.LF & ASCII.HT &
         "mov  r1, #0x3F" & ASCII.LF & ASCII.HT &
         "tst  r0, r1" & ASCII.LF & ASCII.HT &
         "beq  0f" & ASCII.LF & ASCII.HT &
         "mov  r0, #0" & ASCII.LF & ASCII.HT &
         "bx   lr" & ASCII.LF &
         "0:" & ASCII.LF & ASCII.HT &
         --  CPU is running in thread mode.
         --  Check if already running in privileged thread mode
         "mrs  r0, control"  & ASCII.LF & ASCII.HT &
         "mov  r1, #1" & ASCII.LF & ASCII.HT &
         "tst  r0, r1" & ASCII.LF & ASCII.HT &
         "bne  1f" & ASCII.LF & ASCII.HT &
         "mov  r0, #0" & ASCII.LF & ASCII.HT &
         "bx   lr" & ASCII.LF &
         "1:" & ASCII.LF & ASCII.HT &
         --  Switch CPU to privileged thread mode:
         "svc  #0xff" & ASCII.LF & ASCII.HT &
         "mov  r0, #1" & ASCII.LF & ASCII.HT &
         "bx   lr",
         Volatile => True);

      --  We return here in privileged mode

      --  Dummy return, to make the Ada compiler happy
      return True;
   end Enter_Privileged_Mode;

   --------------------------
   -- Exit_Privileged_Mode --
   --------------------------

   procedure Exit_Privileged_Mode
   is
   begin
      System.Machine_Code.Asm
        (Template =>
         --  Set the processor in unprivileged mode
         "mrs  r0, control"  & ASCII.LF & ASCII.HT &
         "orr  r0, r0, #1" & ASCII.LF & ASCII.HT &
         "msr  control, r0" & ASCII.LF & ASCII.HT &
         "isb" & ASCII.LF & ASCII.HT &
         "bx lr",
         Volatile => True);

      --  We return here in privileged mode
   end Exit_Privileged_Mode;

   ----------------
   -- Initialize --
   ----------------

   procedure Initialize is
      Type1_Read_Execute_Permissions : constant Bus_Master_Permissions_Type1 :=
         (User_Mode_Permissions => (Execute_Allowed => 1,
                                    Write_Allowed => 0,
                                    Read_Allowed => 1),
          others => <>);

      CESR_Value : CESR_Register_Type;
      WORD3_Value : WORD3_Register_Type;
      RGDAAC_Value : RGDAAC_Register_Type;
   begin
      pragma Assert (not Memory_Protection_Var.Initialized);

      if System.BB.Parameters.Use_MPU then
         --
         --  Verify that the MPU has enough regions:
         --
         CESR_Value := MPU_Registers.CESR;
         pragma Assert (Natural (CESR_Value.NRGD) <=
                        Num_Mpu_Regions_Table'Last);

         Memory_Protection_Var.Num_Regions :=
            Num_Mpu_Regions_Table (Natural (CESR_Value.NRGD));

         pragma Assert (Memory_Protection_Var.Num_Regions >=
                        MPU_Region_Index_Type'Enum_Rep (
                           MPU_Region_Index_Type'Last));

         --
         --  Disable MPU to configure it:
         --
         MPU_Registers.CESR := (VLD => 0, others => <>);

         --
         --  Make background region only accessible in CPU privleged mode:
         --
         --  NOTE: The background region is defined by default as the whole
         --  address space.
         --  Only its permissions can be changed. To avoid disabling the region
         --  while changing its access permissions, modify register
         --  RGDAAC[region] instead of WORD[region][2].
         --
         RGDAAC_Value :=
            (Bus_Master_CPU_Core_Perms =>
               (Supervisor_Mode_Permissions => Read_Write_Execute_Allowed,
                others => <>),
             others => <>);
         MPU_Registers.RGDAAC (Background_Region'Enum_Rep) := RGDAAC_Value;

         --
         --  Set region 1 for the code in flash to be executable in
         --  unprivileged mode:
         --
         Define_Mpu_Region (
            Global_Unprivileged_Code_Region,
            Cpu_Core0,
            Flash_Text_Start'Address,
            To_Address (To_Integer (Rom_End'Address) - 1),
            Type1_Read_Execute_Permissions,
            Type2_Permissions => (others => <>));

         --
         --  Set remaining regions as invalid to save power
         --
         for I in Global_Unprivileged_Code_Region'Enum_Rep + 1 ..
                  Region_Index_Type'Last loop
            WORD3_Value := (VLD => 0, others => <>);
            MPU_Registers.Region_Descriptors (I).WORD3 := WORD3_Value;
         end loop;

         --
         --  Enable MPU:
         --
         MPU_Registers.CESR := (VLD => 1, others => <>);
      else
         Disable_MPU;
      end if;

      --
      --  NOTE: access to background region will be disabled upon the first
      --  task context switch
      --
      Memory_Protection_Var.Initialized := True;
   end Initialize;

   -----------------
   -- Initialized --
   -----------------

   function Initialized return Boolean is (Memory_Protection_Var.Initialized);

   --------------------------
   -- Is_MPU_Region_In_Use --
   --------------------------

   function Is_MPU_Region_In_Use (MPU_Region_Index : MPU_Region_Index_Type)
      return Boolean
   is
      Region_Index : constant Region_Index_Type := MPU_Region_Index'Enum_Rep;
      WORD3_Value : constant WORD3_Register_Type :=
          MPU_Registers.Region_Descriptors (Region_Index).WORD3;
   begin
      return WORD3_Value.VLD = 1;
   end Is_MPU_Region_In_Use;

   ------------------------------
   -- Undefine_MPU_Data_Region --
   ------------------------------

   procedure Undefine_MPU_Data_Region (
      Data_Region_Index : MPU_Region_Index_Type)
   is
      Region_Index : constant Region_Index_Type :=
         Data_Region_Index'Enum_Rep;
   begin
      --
      --  Disable access to the region:
      --
      MPU_Registers.Region_Descriptors (Region_Index).WORD3 :=
         (VLD => 0, others => <>);
   end Undefine_MPU_Data_Region;

end Memory_Protection;
