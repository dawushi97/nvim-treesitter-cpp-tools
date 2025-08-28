;; Basic class detector to get class name
(class_specifier
    name: (type_identifier) @base_class_name
) @class

;; Pure virtual function detector - simplified approach
(field_declaration
    declarator: (function_declarator)
    default_value: (number_literal)
) @virtual

;; Alternative: declaration pattern
(declaration
    declarator: (function_declarator)
    default_value: (number_literal)
) @virtual
