;; destructor detector - supports function definitions and declarations
(class_specifier
    name: (type_identifier) @class_name
    body: (field_declaration_list
        (function_definition 
            (function_declarator 
                (destructor_name) @destructor
                (parameter_list)
            )
        )
    )
) @class

;; destructor declaration detector - declaration only case
(class_specifier
    name: (type_identifier) @class_name
    body: (field_declaration_list
        (declaration
            (function_declarator 
                (destructor_name) @destructor
                (parameter_list)
            )
        )
    )
) @class

;; destructor detector - alternative pattern for different AST structures
(class_specifier
    name: (type_identifier) @class_name
    body: (field_declaration_list
        (function_definition
            declarator: (function_declarator
                (destructor_name) @destructor
            )
        )
    )
) @class

;assignment constructor detector (definition)
(class_specifier
    name: (type_identifier) @class_name
    body: (field_declaration_list
        (function_definition
            (reference_declarator 
                (function_declarator 
                    (operator_name
                        "operator" "="
                    ) 
                    (parameter_list
                        (parameter_declaration
                            (abstract_reference_declarator "&") 
                        )
                    )
                )
            ) @assignment_operator_reference_declarator
        )
    )
) @class

;assignment constructor detector (declaration)
(class_specifier
    name: (type_identifier) @class_name
    body: (field_declaration_list
        (declaration
            (reference_declarator 
                (function_declarator 
                    (operator_name
                        "operator" "="
                    ) 
                    (parameter_list
                        (parameter_declaration
                            (abstract_reference_declarator "&") 
                        )
                    )
                )
            ) @assignment_operator_reference_declarator
        )
    )
) @class

;assignment constructor detector (field_declaration) 
(class_specifier
    name: (type_identifier) @class_name
    body: (field_declaration_list
        (field_declaration
            (reference_declarator 
                (function_declarator 
                    (operator_name
                        "operator" "="
                    ) 
                    (parameter_list
                        (parameter_declaration
                            (abstract_reference_declarator "&") 
                        )
                    )
                )
            ) @assignment_operator_reference_declarator
        )
    )
) @class

;move assignment constructor detector (definition)
(class_specifier
    name: (type_identifier) @class_name
    body: (field_declaration_list
        (function_definition
            (reference_declarator 
                (function_declarator 
                    (operator_name
                        "operator" "="
                    )  
                    (parameter_list
                        (parameter_declaration
                            (abstract_reference_declarator "&&") 
                        )
                    )
                )
            ) @move_assignment_operator_reference_declarator
        )
    )
) @class

;move assignment constructor detector (field_declaration)
(class_specifier
    name: (type_identifier) @class_name
    body: (field_declaration_list
        (field_declaration
            (reference_declarator 
                (function_declarator 
                    (operator_name
                        "operator" "="
                    )  
                    (parameter_list
                        (parameter_declaration
                            (abstract_reference_declarator "&&") 
                        )
                    )
                )
            ) @move_assignment_operator_reference_declarator
        )
    )
) @class

;copy construct detector (definition)
(class_specifier
    name: (type_identifier) @class_name
    body: (field_declaration_list
        (function_definition
            (function_declarator 
                (parameter_list
                    (parameter_declaration
                        type: (type_identifier) @copy_construct_args
                        (#eq? @copy_construct_args @class_name)
                        declarator: (abstract_reference_declarator "&")
                    )
                )
            )@copy_construct_function_declarator ;since we need the coordinates
        )
    )
) @class

;copy construct detector (declaration)
(class_specifier
    name: (type_identifier) @class_name
    body: (field_declaration_list
        (declaration
            (function_declarator 
                (parameter_list
                    (parameter_declaration
                        type: (type_identifier) @copy_construct_args
                        (#eq? @copy_construct_args @class_name)
                        declarator: (abstract_reference_declarator "&")
                    )
                )
            )@copy_construct_function_declarator ;since we need the coordinates
        )
    )
) @class

;copy construct detector (field_declaration)
(class_specifier
    name: (type_identifier) @class_name
    body: (field_declaration_list
        (field_declaration
            (function_declarator 
                (parameter_list
                    (parameter_declaration
                        type: (type_identifier) @copy_construct_args
                        (#eq? @copy_construct_args @class_name)
                        declarator: (abstract_reference_declarator "&")
                    )
                )
            )@copy_construct_function_declarator ;since we need the coordinates
        )
    )
) @class

;move construct detector (definition)
(class_specifier
    name: (type_identifier) @class_name
    body: (field_declaration_list
        (function_definition
            (function_declarator 
                (parameter_list
                    (parameter_declaration
                        type: (type_identifier) @move_construct_args
                        (#eq? @move_construct_args @class_name)
                        declarator: (abstract_reference_declarator "&&")
                    )
                )
            )@move_construct_function_declarator ;since we need the coordinates
        )
    )
) @class

;move construct detector (declaration)
(class_specifier
    name: (type_identifier) @class_name
    body: (field_declaration_list
        (declaration
            (function_declarator 
                (parameter_list
                    (parameter_declaration
                        type: (type_identifier) @move_construct_args
                        (#eq? @move_construct_args @class_name)
                        declarator: (abstract_reference_declarator "&&")
                    )
                )
            )@move_construct_function_declarator ;since we need the coordinates
        )
    )
) @class

;move construct detector (field_declaration)
(class_specifier
    name: (type_identifier) @class_name
    body: (field_declaration_list
        (field_declaration
            (function_declarator 
                (parameter_list
                    (parameter_declaration
                        type: (type_identifier) @move_construct_args
                        (#eq? @move_construct_args @class_name)
                        declarator: (abstract_reference_declarator "&&")
                    )
                )
            )@move_construct_function_declarator ;since we need the coordinates
        )
    )
) @class
