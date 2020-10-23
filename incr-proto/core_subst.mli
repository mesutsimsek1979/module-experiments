open Core_types

type t = {
  (* types : Modules.path Ident.Map.t ; *)
  modules : Modules.mod_path Ident.Map.t ;
  (* module_types : Modules.path Ident.Map.t ; *)
}

val val_type: t -> val_type -> val_type
val def_type: t -> def_type -> def_type