module type NUM = sig 
  type t
  val ( + ) : t -> t -> t
  val ( - ) : t -> t -> t
  val ( * ) : t -> t -> t
  val ( / ) : t -> t -> t
  val (~- ) : t -> t
  val zero : t
  val one : t
  val of_int : int -> t
end;;

module NUM = struct
  let ( + ) (implicit M : NUM) = M.( + )
  let ( - ) (implicit M : NUM) = M.( - )
  let ( * ) (implicit M : NUM) = M.( * )
  let ( / ) (implicit M : NUM) = M.( / )
  let (~- ) (implicit M : NUM) = M.(~- )
  let zero  (implicit M : NUM) () = M.zero
  let one   (implicit M : NUM) () = M.one
  let (~~)  (implicit M : NUM) = M.of_int
end;;

module type ORD = sig
  type t
  val ( =  ) : t -> t -> bool
  val ( <> ) : t -> t -> bool
  val ( <  ) : t -> t -> bool
  val ( <= ) : t -> t -> bool
  val ( >  ) : t -> t -> bool
  val ( >= ) : t -> t -> bool
end;;

module ORD = struct
  let ( =  ) (implicit M : ORD) = M.( =  )
  let ( <> ) (implicit M : ORD) = M.( <> )
  let ( <  ) (implicit M : ORD) = M.( <  )
  let ( <= ) (implicit M : ORD) = M.( <= )
  let ( >  ) (implicit M : ORD) = M.( >  )
  let ( >= ) (implicit M : ORD) = M.( >= )
end;;

implicit module Int = struct
  type t = int
  let ( + ),( - ),( * ), ( / ), (~- ) = ( + ),( - ),( * ), ( / ), (~- )
  let zero = 0
  let one = 1
  let of_int x = x
  let (( =  ), ( <> ), ( <  ), ( <= ), ( >  ), ( >= ))
    : (t -> t -> bool)
    * (t -> t -> bool)
    * (t -> t -> bool)
    * (t -> t -> bool)
    * (t -> t -> bool)
    * (t -> t -> bool)
    = ( =  ), ( <> ), ( <  ), ( <= ), ( >  ), ( >= ) 
end;;

implicit module Float = struct
  type t = float
  let ( + ),( - ),( * ), ( / ), (~- ) = ( +.),( -.),( *.), ( /.), (~-.)
  let zero = 0.
  let one = 1.
  let of_int = float_of_int
  let (( =  ), ( <> ), ( <  ), ( <= ), ( >  ), ( >= ))
    : (t -> t -> bool)
    * (t -> t -> bool)
    * (t -> t -> bool)
    * (t -> t -> bool)
    * (t -> t -> bool)
    * (t -> t -> bool)
    = ( =  ), ( <> ), ( <  ), ( <= ), ( >  ), ( >= )
end;;

(*implicit module Num_NUM = struct
  open Num
  type t = num
  let ( + ),( - ),( * ), ( / ) = ( +/),( -/),( */), ( //)
  let zero = num_of_int 0
  let one = num_of_int 1
  let (~- ) k = zero - k
  let of_int = float_of_int
  let ( = ), ( <> ), ( < ), ( <= ), ( > ), ( >= )
    = ( =/), ( <>/), ( </), ( <=/), ( >/), ( >=/)
end;;*)

open NUM;;
open ORD;;
assert ( ~~2 / ~~3 = 0
      && ~~2 / ~~3 = 0.666666666666666666666666666666666666);;
let x = 1 + one() + one();;
let () = print_int x;;
