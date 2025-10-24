# Basics

- This project uses the Odin programming language
- Make sure code is clean and well-organized
- Do not add comments, unless absolutely necessary
- When adding any sub-directories, ensure the build.sh is updated for that collection
- Use meaningful names for variables and functions
- Use raylib and imgui
- Do not use the var keyword, variables are declared as var_name: type not var name type
- Structs are declared as StructName :: struct { ... } not StructName { ... }
- Functions are declared as FuncName :: proc(args) -> return_type { ... } not FuncName(args) return_type { ... }
- Use camelCase for variable and function names, and PascalCase for struct names
- Use rl.Vector2{ x, y } to create 2D vectors
- Use rl.Rectangle{ x, y, width, height } to create rectangles
- Use rl.Color{ r, g, b, a } to create colors
- Use cast(type)expression for type casting, not type(expression)
- Create structs via StructName { field1 = "", field2 = 0 } not StructName{ "", 0 } or StructName{ .field1 = "", .field2 = 0 }
