import Foundation

/// `Result<String, String>` no compila en Swift porque `String` no
/// adopta el protocolo `Error`. Para evitar repetir esa misma metida de
/// pata que tuvimos en el widget ToDo (`GhStore` / `JiraStore`), todos
/// los callbacks asíncronos de este paquete usan `Result<T, StringError>`.
struct StringError: LocalizedError, Equatable {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}
