open Peyhel

type t = {
  values : Core_types.val_type Ident.tbl ;
  types : Modules.type_decl Ident.tbl ;
  modules : Modules.mod_type Ident.tbl ;
  module_types : Modules.mod_type Ident.tbl ;
}

type _ key =
  | Value : Core_types.val_type key
  | Type : Modules.type_decl key
  | Module : Modules.mod_type key
  | Module_type : Modules.mod_type key

let empty = {
  values = Ident.Map.empty ;
  types = Ident.Map.empty ;
  modules = Ident.Map.empty ;
  module_types = Ident.Map.empty ;
}

let select (type a) (k : a key) env : a Ident.tbl = match k with
  | Value -> env.values
  | Type -> env.types
  | Module -> env.modules
  | Module_type -> env.module_types

let map (type a) (k : a key) (f : a Ident.tbl -> a Ident.tbl) env =
  match k with
  | Value -> { env with values = f env.values }
  | Type -> { env with types = f env.types }
  | Module -> { env with modules = f env.modules }
  | Module_type -> { env with module_types = env.module_types }

type error =
  | Already_defined of Modules.signature_item

exception Error of error

let add key id v env =
  let f tbl = Ident.Map.add id v tbl in
  map key f env

let add_value = add Value
let add_type = add Type
let add_module = add Module
let add_module_type = add Module_type


let empty_sig id = {Modules.
  sig_self = id ;
  sig_values = Modules.FieldMap.empty ;
  sig_types = Modules.FieldMap.empty ;
  sig_modules = Modules.FieldMap.empty ;
  sig_module_types = Modules.FieldMap.empty ;
}

let fold_with name f env0 l0 =
  let id = Ident.create name in
  let update_sig env signature =
    map Module (Ident.Map.add id (Modules.Core (Signature signature))) env
  in
  let add_item item (s : Modules.signature) = match item with
    | Modules.Value_sig (field, decl) ->
      if Modules.FieldMap.mem field s.sig_values then
        raise (Error (Already_defined item));
      let sig_values = Modules.FieldMap.add field decl s.sig_values in
      {s with sig_values }
    | Type_sig (field, decl) ->
      if Modules.FieldMap.mem field s.sig_types then
        raise (Error (Already_defined item));
      let sig_types = Modules.FieldMap.add field decl s.sig_types in
      {s with sig_types }
    | Module_sig (field, decl) ->
      if Modules.FieldMap.mem field s.sig_modules then
        raise (Error (Already_defined item));
      let sig_modules = Modules.FieldMap.add field decl s.sig_modules in
      {s with sig_modules }
    | Module_type_sig (field, decl) ->
      if Modules.FieldMap.mem field s.sig_module_types then
        raise (Error (Already_defined item));
      let sig_module_types = Modules.FieldMap.add field decl s.sig_module_types in
      {s with sig_module_types }
  in
  let rec aux_fold env signature = function
    | [] -> signature
    | h :: t ->
      let env = update_sig env signature in
      let item = f env h in
      let signature = add_item item signature in
      aux_fold env signature t
  in
  let sig0 = empty_sig id in
  aux_fold env0 sig0 l0

let intro key name v env =
  let id = Ident.create name in
  let f tbl =
    Ident.Map.add id v tbl
  in
  id, map key f env

let intro_value = intro Value
let intro_type = intro Type
let intro_module = intro Module
let intro_module_type = intro Module_type

let lookup_in_env
  : type a . key:a key -> _ -> _ -> a
  = fun ~key id env ->
    Ident.Map.lookup id (select key env)

let compute_signature
  : (t -> Modules.mod_type -> Modules.signature) ref
  = ref (fun _ _ -> assert false)

let compute_ascription
  : (t -> Modules.mod_type -> Modules.mod_type -> Modules.mod_type) ref
  = ref (fun _ _ _ -> assert false)

let compute_functor_app
  : (t -> f:Modules.mod_type -> arg:Modules.mod_path -> Modules.mod_type) ref
  = ref (fun _ ~f:_ ~arg:_ -> assert false)

let lookup_raw_in_sig
  : type a . key:a key -> Modules.field -> Modules.signature -> a
  = fun ~key field s ->
    match key with
    | Value -> Modules.FieldMap.find field s.sig_values
    | Type -> Modules.FieldMap.find field s.sig_types
    | Module -> Modules.FieldMap.find field s.sig_modules
    | Module_type -> Modules.FieldMap.find field s.sig_module_types

let subst_self_in_sig
  : type a . self:Ident.t -> path:Modules.mod_path -> sort:a key -> a -> a
  = fun ~self ~path ~sort x ->
    let subst = Subst.add_module self path Subst.identity in
    let f : _ -> a -> a = match sort with
      | Value -> Subst.val_type
      | Type -> Subst.type_decl
      | Module -> Subst.mod_type
      | Module_type -> Subst.mod_type
    in
    f subst x

let lookup_in_sig ~key path field s =
  let elt = lookup_raw_in_sig ~key field s in
  subst_self_in_sig ~self:s.sig_self ~path ~sort:key elt

let rec lookup_module : t -> Modules.mod_path -> _
  = fun env path0 ->
    match path0 with
    | Id id ->
      let mty = lookup_in_env ~key:Module id env in
      mty
    | Proj {path; field} ->
      let path_mty = lookup_module env path in
      let s = !compute_signature env path_mty in
      lookup_in_sig ~key:Module path field s
    | Ascription (path, ascr_mty) -> 
      let path_mty = lookup_module env path in
      let mty = !compute_ascription env path_mty ascr_mty in
      mty
    | Apply (path_f, path_arg) ->
      let mty_f = lookup_module env path_f in
      let mty = !compute_functor_app env ~f:mty_f ~arg:path_arg in
      mty

let lookup : type a . a key -> t -> Modules.path -> a option
  = fun key env {Modules. path ; field } ->
    try 
      let path_mty = lookup_module env path in
      let s = !compute_signature env path_mty in
      let v = lookup_in_sig ~key path field s in
      Some v
    with
    | Not_found -> None

let lookup_module env p = try Some (lookup_module env p) with Not_found -> None
let lookup_value = lookup Value
let lookup_type = lookup Type
let lookup_module_type = lookup Module_type

let find_root_module env id =
  try 
    let id, _ = Ident.Map.find id (select Module env) in
    Some id
  with Not_found -> None


(** Errors *)
  
let prepare_error = function
  | Already_defined item ->
    let sort, name = match item with
      | Modules.Value_sig (s,_) -> "value", s
      | Modules.Type_sig (s,_) -> "type", s
      | Modules.Module_sig (s,_) -> "module", s
      | Modules.Module_type_sig (s,_) -> "module type", s
    in
    Report.errorf "The %s %s is already defined" sort name
  
let () = Report.register_report_of_exn @@ function
  | Error e -> Some (prepare_error e)
  | _ -> None

