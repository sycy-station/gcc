------------------------------------------------------------------------------
--                                                                          --
--                         GNAT COMPILER COMPONENTS                         --
--                                                                          --
--                             E X P _ A T A G                              --
--                                                                          --
--                                 B o d y                                  --
--                                                                          --
--          Copyright (C) 2006-2025, Free Software Foundation, Inc.         --
--                                                                          --
-- GNAT is free software;  you can  redistribute it  and/or modify it under --
-- terms of the  GNU General Public License as published  by the Free Soft- --
-- ware  Foundation;  either version 3,  or (at your option) any later ver- --
-- sion.  GNAT is distributed in the hope that it will be useful, but WITH- --
-- OUT ANY WARRANTY;  without even the  implied warranty of MERCHANTABILITY --
-- or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License --
-- for  more details.  You should have  received  a copy of the GNU General --
-- Public License  distributed with GNAT; see file COPYING3.  If not, go to --
-- http://www.gnu.org/licenses for a complete copy of the license.          --
--                                                                          --
-- GNAT was originally developed  by the GNAT team at  New York University. --
-- Extensive contributions were provided by Ada Core Technologies Inc.      --
--                                                                          --
------------------------------------------------------------------------------

with Atree;          use Atree;
with Einfo;          use Einfo;
with Einfo.Entities; use Einfo.Entities;
with Einfo.Utils;    use Einfo.Utils;
with Elists;         use Elists;
with Exp_Disp;       use Exp_Disp;
with Namet;          use Namet;
with Nlists;         use Nlists;
with Nmake;          use Nmake;
with Opt;            use Opt;
with Rtsfind;        use Rtsfind;
with Sinfo;          use Sinfo;
with Sinfo.Nodes;    use Sinfo.Nodes;
with Sinfo.Utils;    use Sinfo.Utils;
with Sem_Aux;        use Sem_Aux;
with Sem_Disp;       use Sem_Disp;
with Sem_Util;       use Sem_Util;
with Stand;          use Stand;
with Snames;         use Snames;
with Tbuild;         use Tbuild;

package body Exp_Atag is

   -----------------------
   -- Local Subprograms --
   -----------------------

   function Build_DT
     (Loc      : Source_Ptr;
      Tag_Node : Node_Id) return Node_Id;
   --  Build code that displaces the Tag to reference the base of the wrapper
   --  record
   --
   --  Generates:
   --    To_Dispatch_Table_Ptr
   --      (To_Address (Tag_Node) - Tag_Node.Prims_Ptr'Position);

   function Build_Range (Loc : Source_Ptr; Lo, Hi : Nat) return Node_Id;
   --  Build an N_Range node for [Lo; Hi] with Standard.Natural type

   function Build_TSD
     (Loc           : Source_Ptr;
      Tag_Node_Addr : Node_Id) return Node_Id;
   --  Build code that retrieves the address of the record containing the Type
   --  Specific Data generated by GNAT.
   --
   --  Generate: To_Type_Specific_Data_Ptr
   --              (To_Addr_Ptr (Tag_Node_Addr - Typeinfo_Offset).all);

   function Build_Val (Loc : Source_Ptr; V : Uint) return Node_Id;
   --  Build an N_Integer_Literal node for V with Standard.Natural type

   ------------------------------------------------
   -- Build_Common_Dispatching_Select_Statements --
   ------------------------------------------------

   procedure Build_Common_Dispatching_Select_Statements
     (Typ    : Entity_Id;
      Stmts  : List_Id)
   is
      Loc      : constant Source_Ptr := Sloc (Typ);
      Tag_Node : Node_Id;

   begin
      --  Generate:
      --    C := get_prim_op_kind (tag! (<type>VP), S);

      --  where C is the out parameter capturing the call kind and S is the
      --  dispatch table slot number.

      if Tagged_Type_Expansion then
         Tag_Node :=
           Unchecked_Convert_To (RTE (RE_Tag),
             New_Occurrence_Of
              (Node (First_Elmt (Access_Disp_Table (Typ))), Loc));

      else
         Tag_Node :=
           Make_Attribute_Reference (Loc,
             Prefix => New_Occurrence_Of (Typ, Loc),
             Attribute_Name => Name_Tag);
      end if;

      Append_To (Stmts,
        Make_Assignment_Statement (Loc,
          Name       => Make_Identifier (Loc, Name_uC),
          Expression =>
            Make_Function_Call (Loc,
              Name                   =>
                New_Occurrence_Of (RTE (RE_Get_Prim_Op_Kind), Loc),
              Parameter_Associations => New_List (
                Tag_Node,
                Make_Identifier (Loc, Name_uS)))));

      --  Generate:

      --    if C = POK_Procedure
      --      or else C = POK_Protected_Procedure
      --      or else C = POK_Task_Procedure;
      --    then
      --       F := True;
      --       return;

      --  where F is the out parameter capturing the status of a potential
      --  entry call.

      Append_To (Stmts,
        Make_If_Statement (Loc,

          Condition =>
            Make_Or_Else (Loc,
              Left_Opnd =>
                Make_Op_Eq (Loc,
                  Left_Opnd  => Make_Identifier (Loc, Name_uC),
                  Right_Opnd =>
                    New_Occurrence_Of (RTE (RE_POK_Procedure), Loc)),
              Right_Opnd =>
                Make_Or_Else (Loc,
                  Left_Opnd =>
                    Make_Op_Eq (Loc,
                      Left_Opnd => Make_Identifier (Loc, Name_uC),
                      Right_Opnd =>
                        New_Occurrence_Of
                          (RTE (RE_POK_Protected_Procedure), Loc)),
                  Right_Opnd =>
                    Make_Op_Eq (Loc,
                      Left_Opnd  => Make_Identifier (Loc, Name_uC),
                      Right_Opnd =>
                        New_Occurrence_Of
                          (RTE (RE_POK_Task_Procedure), Loc)))),

          Then_Statements =>
            New_List (
              Make_Assignment_Statement (Loc,
                Name       => Make_Identifier (Loc, Name_uF),
                Expression => New_Occurrence_Of (Standard_True, Loc)),
              Make_Simple_Return_Statement (Loc))));
   end Build_Common_Dispatching_Select_Statements;

   --------------
   -- Build_DT --
   --------------

   function Build_DT
     (Loc      : Source_Ptr;
      Tag_Node : Node_Id) return Node_Id
   is
   begin
      return
        Make_Function_Call (Loc,
          Name => New_Occurrence_Of (RTE (RE_DT), Loc),
          Parameter_Associations => New_List (
            Unchecked_Convert_To (RTE (RE_Tag), Tag_Node)));
   end Build_DT;

   ----------------------------
   -- Build_Get_Access_Level --
   ----------------------------

   function Build_Get_Access_Level
     (Loc      : Source_Ptr;
      Tag_Node : Node_Id) return Node_Id
   is
   begin
      return
        Make_Selected_Component (Loc,
          Prefix =>
            Make_Explicit_Dereference (Loc,
              Build_TSD (Loc,
                Unchecked_Convert_To (RTE (RE_Address), Tag_Node))),
          Selector_Name =>
            New_Occurrence_Of
              (RTE_Record_Component (RE_Access_Level), Loc));
   end Build_Get_Access_Level;

   -------------------------
   -- Build_Get_Alignment --
   -------------------------

   function Build_Get_Alignment
     (Loc      : Source_Ptr;
      Tag_Node : Node_Id) return Node_Id
   is
   begin
      return
        Make_Selected_Component (Loc,
          Prefix =>
            Make_Explicit_Dereference (Loc,
              Build_TSD (Loc,
                Unchecked_Convert_To (RTE (RE_Address), Tag_Node))),
          Selector_Name =>
            New_Occurrence_Of (RTE_Record_Component (RE_Alignment), Loc));
   end Build_Get_Alignment;

   ------------------------------------------
   -- Build_Get_Predefined_Prim_Op_Address --
   ------------------------------------------

   procedure Build_Get_Predefined_Prim_Op_Address
     (Loc      : Source_Ptr;
      Position : Uint;
      Tag_Node : in out Node_Id;
      New_Node : out Node_Id)
   is
      Ctrl_Tag : Node_Id;

   begin
      Ctrl_Tag := Unchecked_Convert_To (RTE (RE_Address), Tag_Node);

      --  Unchecked_Convert_To relocates the controlling tag node and therefore
      --  we must update it.

      Tag_Node := Expression (Ctrl_Tag);

      --  Build code that retrieves the address of the dispatch table
      --  containing the predefined Ada primitives:
      --
      --  Generate:
      --    To_Predef_Prims_Table_Ptr
      --     (To_Addr_Ptr (To_Address (Tag) - Predef_Prims_Offset).all);

      New_Node :=
        Make_Indexed_Component (Loc,
          Prefix =>
            Unchecked_Convert_To (RTE (RE_Predef_Prims_Table_Ptr),
              Make_Explicit_Dereference (Loc,
                Unchecked_Convert_To (RTE (RE_Addr_Ptr),
                  Make_Function_Call (Loc,
                    Name =>
                      Make_Expanded_Name (Loc,
                        Chars => Name_Op_Subtract,
                        Prefix =>
                          New_Occurrence_Of
                            (RTU_Entity (System_Storage_Elements), Loc),
                        Selector_Name =>
                          Make_Identifier (Loc, Name_Op_Subtract)),
                    Parameter_Associations => New_List (
                      Ctrl_Tag,
                      New_Occurrence_Of
                        (RTE (RE_DT_Predef_Prims_Offset), Loc)))))),
          Expressions =>
            New_List (Build_Val (Loc, Position)));
   end Build_Get_Predefined_Prim_Op_Address;

   -----------------------------
   -- Build_Inherit_CPP_Prims --
   -----------------------------

   function Build_Inherit_CPP_Prims (Typ : Entity_Id) return List_Id is
      Loc          : constant Source_Ptr := Sloc (Typ);
      CPP_Nb_Prims : constant Nat := CPP_Num_Prims (Typ);
      CPP_Table    : array (1 .. CPP_Nb_Prims) of Boolean := (others => False);
      CPP_Typ      : constant Entity_Id := Enclosing_CPP_Parent (Typ);
      Result       : constant List_Id   := New_List;
      Parent_Typ   : constant Entity_Id := Etype (Typ);
      E            : Entity_Id;
      Elmt         : Elmt_Id;
      Parent_Tag   : Entity_Id;
      Prim         : Entity_Id;
      Prim_Pos     : Nat;
      Typ_Tag      : Entity_Id;

   begin
      pragma Assert (not Is_CPP_Class (Typ));

      --  No code needed if this type has no primitives inherited from C++

      if CPP_Nb_Prims = 0 then
         return Result;
      end if;

      --  Stage 1: Inherit and override C++ slots of the primary dispatch table

      --  Generate:
      --     Typ'Tag (Prim_Pos) := Prim'Unrestricted_Access;

      Parent_Tag := Node (First_Elmt (Access_Disp_Table (Parent_Typ)));
      Typ_Tag    := Node (First_Elmt (Access_Disp_Table (Typ)));

      Elmt := First_Elmt (Primitive_Operations (Typ));
      while Present (Elmt) loop
         Prim     := Node (Elmt);
         E        := Ultimate_Alias (Prim);
         Prim_Pos := UI_To_Int (DT_Position (E));

         --  Skip predefined, abstract, and eliminated primitives. Skip also
         --  primitives not located in the C++ part of the dispatch table.

         if not Is_Predefined_Dispatching_Operation (Prim)
           and then not Is_Predefined_Dispatching_Operation (E)
           and then No (Interface_Alias (Prim))
           and then not Is_Abstract_Subprogram (E)
           and then not Is_Eliminated (E)
           and then Prim_Pos <= CPP_Nb_Prims
           and then Find_Dispatching_Type (E) = Typ
         then
            --  Remember that this slot is used

            pragma Assert (CPP_Table (Prim_Pos) = False);
            CPP_Table (Prim_Pos) := True;

            Append_To (Result,
              Make_Assignment_Statement (Loc,
                Name      =>
                  Make_Indexed_Component (Loc,
                    Prefix      =>
                      Make_Explicit_Dereference (Loc,
                        Unchecked_Convert_To
                          (Node (Last_Elmt (Access_Disp_Table (Typ))),
                           New_Occurrence_Of (Typ_Tag, Loc))),
                    Expressions =>
                       New_List (Build_Val (Loc, UI_From_Int (Prim_Pos)))),

               Expression =>
                 Unchecked_Convert_To (RTE (RE_Prim_Ptr),
                   Make_Attribute_Reference (Loc,
                     Prefix         => New_Occurrence_Of (E, Loc),
                     Attribute_Name => Name_Unrestricted_Access))));
         end if;

         Next_Elmt (Elmt);
      end loop;

      --  If all primitives have been overridden then there is no need to copy
      --  from Typ's parent its dispatch table. Otherwise, if some primitive is
      --  inherited from the parent we copy only the C++ part of the dispatch
      --  table from the parent before the assignments that initialize the
      --  overridden primitives.

      --  Generate:

      --     type CPP_TypG is array (1 .. CPP_Nb_Prims) ofd Prim_Ptr;
      --     type CPP_TypH is access CPP_TypG;
      --     CPP_TypG!(Typ_Tag).all := CPP_TypG!(Parent_Tag).all;

      --   Note: There is no need to duplicate the declarations of CPP_TypG and
      --         CPP_TypH because, for expansion of dispatching calls, these
      --         entities are stored in the last elements of Access_Disp_Table.

      for J in CPP_Table'Range loop
         if not CPP_Table (J) then
            Prepend_To (Result,
              Make_Assignment_Statement (Loc,
                Name       =>
                  Make_Explicit_Dereference (Loc,
                    Unchecked_Convert_To
                      (Node (Last_Elmt (Access_Disp_Table (CPP_Typ))),
                       New_Occurrence_Of (Typ_Tag, Loc))),
                Expression =>
                  Make_Explicit_Dereference (Loc,
                    Unchecked_Convert_To
                      (Node (Last_Elmt (Access_Disp_Table (CPP_Typ))),
                       New_Occurrence_Of (Parent_Tag, Loc)))));
            exit;
         end if;
      end loop;

      --  Stage 2: Inherit and override C++ slots of secondary dispatch tables

      declare
         Iface                   : Entity_Id;
         Iface_Nb_Prims          : Nat;
         Parent_Ifaces_List      : Elist_Id;
         Parent_Ifaces_Comp_List : Elist_Id;
         Parent_Ifaces_Tag_List  : Elist_Id;
         Parent_Iface_Tag_Elmt   : Elmt_Id;
         Typ_Ifaces_List         : Elist_Id;
         Typ_Ifaces_Comp_List    : Elist_Id;
         Typ_Ifaces_Tag_List     : Elist_Id;
         Typ_Iface_Tag_Elmt      : Elmt_Id;

      begin
         Collect_Interfaces_Info
           (T               => Parent_Typ,
            Ifaces_List     => Parent_Ifaces_List,
            Components_List => Parent_Ifaces_Comp_List,
            Tags_List       => Parent_Ifaces_Tag_List);

         Collect_Interfaces_Info
           (T               => Typ,
            Ifaces_List     => Typ_Ifaces_List,
            Components_List => Typ_Ifaces_Comp_List,
            Tags_List       => Typ_Ifaces_Tag_List);

         Parent_Iface_Tag_Elmt := First_Elmt (Parent_Ifaces_Tag_List);
         Typ_Iface_Tag_Elmt    := First_Elmt (Typ_Ifaces_Tag_List);
         while Present (Parent_Iface_Tag_Elmt) loop
            Parent_Tag := Node (Parent_Iface_Tag_Elmt);
            Typ_Tag    := Node (Typ_Iface_Tag_Elmt);

            pragma Assert
              (Related_Type (Parent_Tag) = Related_Type (Typ_Tag));
            Iface := Related_Type (Parent_Tag);

            Iface_Nb_Prims :=
              UI_To_Int (DT_Entry_Count (First_Tag_Component (Iface)));

            if Iface_Nb_Prims > 0 then

               --  Update slots of overridden primitives

               declare
                  Last_Nod : constant Node_Id := Last (Result);
                  Nb_Prims : constant Nat := UI_To_Int
                                              (DT_Entry_Count
                                               (First_Tag_Component (Iface)));
                  Elmt     : Elmt_Id;
                  Prim     : Entity_Id;
                  E        : Entity_Id;
                  Prim_Pos : Nat;

                  Prims_Table : array (1 .. Nb_Prims) of Boolean;

               begin
                  Prims_Table := (others => False);

                  Elmt := First_Elmt (Primitive_Operations (Typ));
                  while Present (Elmt) loop
                     Prim := Node (Elmt);
                     E    := Ultimate_Alias (Prim);

                     if not Is_Predefined_Dispatching_Operation (Prim)
                       and then Present (Interface_Alias (Prim))
                       and then Find_Dispatching_Type (Interface_Alias (Prim))
                                  = Iface
                       and then not Is_Abstract_Subprogram (E)
                       and then not Is_Eliminated (E)
                       and then Find_Dispatching_Type (E) = Typ
                     then
                        Prim_Pos := UI_To_Int (DT_Position (Prim));

                        --  Remember that this slot is already initialized

                        pragma Assert (Prims_Table (Prim_Pos) = False);
                        Prims_Table (Prim_Pos) := True;

                        Append_To (Result,
                          Make_Assignment_Statement (Loc,
                            Name       =>
                              Make_Indexed_Component (Loc,
                                Prefix      =>
                                  Make_Explicit_Dereference (Loc,
                                    Unchecked_Convert_To
                                      (Node
                                        (Last_Elmt
                                           (Access_Disp_Table (Iface))),
                                       New_Occurrence_Of (Typ_Tag, Loc))),
                                Expressions =>
                                   New_List
                                    (Build_Val (Loc, UI_From_Int (Prim_Pos)))),

                            Expression =>
                              Unchecked_Convert_To (RTE (RE_Prim_Ptr),
                                Make_Attribute_Reference (Loc,
                                  Prefix         => New_Occurrence_Of (E, Loc),
                                  Attribute_Name =>
                                    Name_Unrestricted_Access))));
                     end if;

                     Next_Elmt (Elmt);
                  end loop;

                  --  Check if all primitives from the parent have been
                  --  overridden (to avoid copying the whole secondary
                  --  table from the parent).

                  --   IfaceG!(Typ_Sec_Tag).all := IfaceG!(Parent_Sec_Tag).all;

                  for J in Prims_Table'Range loop
                     if not Prims_Table (J) then
                        Insert_After (Last_Nod,
                          Make_Assignment_Statement (Loc,
                            Name       =>
                              Make_Explicit_Dereference (Loc,
                                Unchecked_Convert_To
                                 (Node (Last_Elmt (Access_Disp_Table (Iface))),
                                  New_Occurrence_Of (Typ_Tag, Loc))),
                            Expression =>
                              Make_Explicit_Dereference (Loc,
                                Unchecked_Convert_To
                                 (Node (Last_Elmt (Access_Disp_Table (Iface))),
                                  New_Occurrence_Of (Parent_Tag, Loc)))));
                        exit;
                     end if;
                  end loop;
               end;
            end if;

            Next_Elmt (Typ_Iface_Tag_Elmt);
            Next_Elmt (Parent_Iface_Tag_Elmt);
         end loop;
      end;

      return Result;
   end Build_Inherit_CPP_Prims;

   -------------------------
   -- Build_Inherit_Prims --
   -------------------------

   function Build_Inherit_Prims
     (Loc          : Source_Ptr;
      Typ          : Entity_Id;
      Old_Tag_Node : Node_Id;
      New_Tag_Node : Node_Id;
      Num_Prims    : Nat) return Node_Id
   is
   begin
      if RTE_Available (RE_DT) then
         return
           Make_Assignment_Statement (Loc,
             Name =>
               Make_Slice (Loc,
                 Prefix =>
                   Make_Selected_Component (Loc,
                     Prefix =>
                       Make_Explicit_Dereference (Loc,
                         Build_DT (Loc, New_Tag_Node)),
                     Selector_Name =>
                       New_Occurrence_Of
                         (RTE_Record_Component (RE_Prims_Ptr), Loc)),
                 Discrete_Range =>
                   Build_Range (Loc, 1, Num_Prims)),

             Expression =>
               Make_Slice (Loc,
                 Prefix =>
                   Make_Selected_Component (Loc,
                     Prefix =>
                       Make_Explicit_Dereference (Loc,
                         Build_DT (Loc, Old_Tag_Node)),
                     Selector_Name =>
                       New_Occurrence_Of
                         (RTE_Record_Component (RE_Prims_Ptr), Loc)),
                 Discrete_Range =>
                   Build_Range (Loc, 1, Num_Prims)));
      else
         return
           Make_Assignment_Statement (Loc,
             Name =>
               Make_Slice (Loc,
                 Prefix =>
                   Unchecked_Convert_To
                     (Node (Last_Elmt (Access_Disp_Table (Typ))),
                      New_Tag_Node),
                 Discrete_Range =>
                   Build_Range (Loc, 1, Num_Prims)),

             Expression =>
               Make_Slice (Loc,
                 Prefix =>
                   Unchecked_Convert_To
                     (Node (Last_Elmt (Access_Disp_Table (Typ))),
                      Old_Tag_Node),
                 Discrete_Range =>
                   Build_Range (Loc, 1, Num_Prims)));
      end if;
   end Build_Inherit_Prims;

   -------------------------------
   -- Build_Get_Prim_Op_Address --
   -------------------------------

   procedure Build_Get_Prim_Op_Address
     (Loc      : Source_Ptr;
      Typ      : Entity_Id;
      Position : Uint;
      Tag_Node : in out Node_Id;
      New_Node : out Node_Id)
   is
      New_Prefix : Node_Id;

   begin
      pragma Assert
        (Position <= DT_Entry_Count (First_Tag_Component (Typ)));

      --  At the end of the Access_Disp_Table list we have the type
      --  declaration required to convert the tag into a pointer to
      --  the prims_ptr table (see Freeze_Record_Type).

      New_Prefix :=
        Unchecked_Convert_To
          (Node (Last_Elmt (Access_Disp_Table (Typ))), Tag_Node);

      --  Unchecked_Convert_To relocates the controlling tag node and therefore
      --  we must update it.

      Tag_Node := Expression (New_Prefix);

      New_Node :=
        Make_Indexed_Component (Loc,
          Prefix      => New_Prefix,
          Expressions => New_List (Build_Val (Loc, Position)));
   end Build_Get_Prim_Op_Address;

   -----------------------------
   -- Build_Get_Transportable --
   -----------------------------

   function Build_Get_Transportable
     (Loc      : Source_Ptr;
      Tag_Node : Node_Id) return Node_Id
   is
   begin
      return
        Make_Selected_Component (Loc,
          Prefix =>
            Make_Explicit_Dereference (Loc,
              Build_TSD (Loc,
                Unchecked_Convert_To (RTE (RE_Address), Tag_Node))),
          Selector_Name =>
            New_Occurrence_Of
              (RTE_Record_Component (RE_Transportable), Loc));
   end Build_Get_Transportable;

   ------------------------------------
   -- Build_Inherit_Predefined_Prims --
   ------------------------------------

   function Build_Inherit_Predefined_Prims
     (Loc              : Source_Ptr;
      Old_Tag_Node     : Node_Id;
      New_Tag_Node     : Node_Id;
      Num_Predef_Prims : Nat) return Node_Id
   is
   begin
      return
        Make_Assignment_Statement (Loc,
          Name =>
            Make_Slice (Loc,
              Prefix =>
                Make_Explicit_Dereference (Loc,
                  Unchecked_Convert_To (RTE (RE_Predef_Prims_Table_Ptr),
                    Make_Explicit_Dereference (Loc,
                      Unchecked_Convert_To (RTE (RE_Addr_Ptr),
                        New_Tag_Node)))),
              Discrete_Range =>
                Build_Range (Loc, 1, Num_Predef_Prims)),

          Expression =>
            Make_Slice (Loc,
              Prefix =>
                Make_Explicit_Dereference (Loc,
                  Unchecked_Convert_To (RTE (RE_Predef_Prims_Table_Ptr),
                    Make_Explicit_Dereference (Loc,
                      Unchecked_Convert_To (RTE (RE_Addr_Ptr),
                        Old_Tag_Node)))),
              Discrete_Range =>
                Build_Range (Loc, 1, Num_Predef_Prims)));
   end Build_Inherit_Predefined_Prims;

   -------------------------
   -- Build_Offset_To_Top --
   -------------------------

   function Build_Offset_To_Top
     (Loc       : Source_Ptr;
      This_Node : Node_Id) return Node_Id
   is
      Tag_Node : Node_Id;

   begin
      Tag_Node :=
        Make_Explicit_Dereference (Loc,
          Unchecked_Convert_To (RTE (RE_Tag_Ptr), This_Node));

      return
        Make_Explicit_Dereference (Loc,
          Unchecked_Convert_To (RTE (RE_Offset_To_Top_Ptr),
            Make_Function_Call (Loc,
              Name =>
                Make_Expanded_Name (Loc,
                  Chars         => Name_Op_Subtract,
                  Prefix        =>
                    New_Occurrence_Of
                      (RTU_Entity (System_Storage_Elements), Loc),
                  Selector_Name => Make_Identifier (Loc, Name_Op_Subtract)),
              Parameter_Associations => New_List (
                Unchecked_Convert_To (RTE (RE_Address), Tag_Node),
                New_Occurrence_Of
                  (RTE (RE_DT_Offset_To_Top_Offset), Loc)))));
   end Build_Offset_To_Top;

   -----------------
   -- Build_Range --
   -----------------

   function Build_Range (Loc : Source_Ptr; Lo, Hi : Nat) return Node_Id is
      Result : Node_Id;

   begin
      Result :=
        Make_Range (Loc,
           Low_Bound  => Build_Val (Loc, UI_From_Int (Lo)),
           High_Bound => Build_Val (Loc, UI_From_Int (Hi)));
      Set_Etype (Result, Standard_Natural);
      Set_Analyzed (Result);
      return Result;
   end Build_Range;

   ------------------------------------------
   -- Build_Set_Predefined_Prim_Op_Address --
   ------------------------------------------

   function Build_Set_Predefined_Prim_Op_Address
     (Loc          : Source_Ptr;
      Tag_Node     : Node_Id;
      Position     : Uint;
      Address_Node : Node_Id) return Node_Id
   is
   begin
      return
         Make_Assignment_Statement (Loc,
           Name =>
             Make_Indexed_Component (Loc,
               Prefix =>
                 Unchecked_Convert_To (RTE (RE_Predef_Prims_Table_Ptr),
                   Make_Explicit_Dereference (Loc,
                     Unchecked_Convert_To (RTE (RE_Addr_Ptr), Tag_Node))),
               Expressions =>
                 New_List (Build_Val (Loc, Position))),

           Expression => Address_Node);
   end Build_Set_Predefined_Prim_Op_Address;

   -------------------------------
   -- Build_Set_Prim_Op_Address --
   -------------------------------

   function Build_Set_Prim_Op_Address
     (Loc          : Source_Ptr;
      Typ          : Entity_Id;
      Tag_Node     : Node_Id;
      Position     : Uint;
      Address_Node : Node_Id) return Node_Id
   is
      Ctrl_Tag : Node_Id := Tag_Node;
      New_Node : Node_Id;

   begin
      Build_Get_Prim_Op_Address (Loc, Typ, Position, Ctrl_Tag, New_Node);

      return
        Make_Assignment_Statement (Loc,
          Name       => New_Node,
          Expression => Address_Node);
   end Build_Set_Prim_Op_Address;

   -----------------------------
   -- Build_Set_Size_Function --
   -----------------------------

   function Build_Set_Size_Function
     (Loc       : Source_Ptr;
      Typ       : Entity_Id;
      Size_Func : Entity_Id) return Node_Id
   is
      F_Nod : constant Node_Id := Freeze_Node (Typ);

      Act : Node_Id;

   begin
      pragma Assert (Chars (Size_Func) = Name_uSize
        and then RTE_Record_Component_Available (RE_Size_Func)
        and then Present (F_Nod));

      --  Find the declaration of the TSD object in the freeze actions

      Act := First (Actions (F_Nod));
      while Present (Act) loop
         if Nkind (Act) = N_Object_Declaration
           and then Nkind (Object_Definition (Act)) = N_Subtype_Indication
           and then Is_Entity_Name (Subtype_Mark (Object_Definition (Act)))
           and then Is_RTE (Entity (Subtype_Mark (Object_Definition (Act))),
                            RE_Type_Specific_Data)
         then
            exit;
         end if;

         Next (Act);
      end loop;

      pragma Assert (Present (Act));

      --  Generate:
      --    TSD.Size_Func := Size_Ptr!(Size_Func'Unrestricted_Access);

      return
        Make_Assignment_Statement (Loc,
          Name =>
            Make_Selected_Component (Loc,
              Prefix        =>
                New_Occurrence_Of (Defining_Identifier (Act), Loc),
              Selector_Name =>
                New_Occurrence_Of
                  (RTE_Record_Component (RE_Size_Func), Loc)),
          Expression =>
            Unchecked_Convert_To (RTE (RE_Size_Ptr),
              Make_Attribute_Reference (Loc,
                Prefix => New_Occurrence_Of (Size_Func, Loc),
                Attribute_Name => Name_Unrestricted_Access)));
   end Build_Set_Size_Function;

   ------------------------------------
   -- Build_Set_Static_Offset_To_Top --
   ------------------------------------

   function Build_Set_Static_Offset_To_Top
     (Loc          : Source_Ptr;
      Iface_Tag    : Node_Id;
      Offset_Value : Node_Id) return Node_Id is
   begin
      return
        Make_Assignment_Statement (Loc,
          Make_Explicit_Dereference (Loc,
            Unchecked_Convert_To (RTE (RE_Offset_To_Top_Ptr),
              Make_Function_Call (Loc,
                Name =>
                  Make_Expanded_Name (Loc,
                    Chars         => Name_Op_Subtract,
                    Prefix        =>
                      New_Occurrence_Of
                        (RTU_Entity (System_Storage_Elements), Loc),
                    Selector_Name => Make_Identifier (Loc, Name_Op_Subtract)),
                Parameter_Associations => New_List (
                  Unchecked_Convert_To (RTE (RE_Address), Iface_Tag),
                  New_Occurrence_Of
                    (RTE (RE_DT_Offset_To_Top_Offset), Loc))))),
          Offset_Value);
   end Build_Set_Static_Offset_To_Top;

   ---------------
   -- Build_TSD --
   ---------------

   function Build_TSD
     (Loc           : Source_Ptr;
      Tag_Node_Addr : Node_Id) return Node_Id is
   begin
      return
        Unchecked_Convert_To (RTE (RE_Type_Specific_Data_Ptr),
          Make_Explicit_Dereference (Loc,
            Prefix => Unchecked_Convert_To (RTE (RE_Addr_Ptr),
              Make_Function_Call (Loc,
                Name =>
                  Make_Expanded_Name (Loc,
                    Chars => Name_Op_Subtract,
                    Prefix =>
                      New_Occurrence_Of
                        (RTU_Entity (System_Storage_Elements), Loc),
                    Selector_Name => Make_Identifier (Loc, Name_Op_Subtract)),

                Parameter_Associations => New_List (
                  Tag_Node_Addr,
                  New_Occurrence_Of
                    (RTE (RE_DT_Typeinfo_Ptr_Size), Loc))))));
   end Build_TSD;

   ---------------
   -- Build_Val --
   ---------------

   function Build_Val (Loc : Source_Ptr; V : Uint) return Node_Id is
      Result : Node_Id;

   begin
      Result := Make_Integer_Literal (Loc, V);
      Set_Etype (Result, Standard_Natural);
      Set_Is_Static_Expression (Result);
      Set_Analyzed (Result);
      return Result;
   end Build_Val;

end Exp_Atag;
