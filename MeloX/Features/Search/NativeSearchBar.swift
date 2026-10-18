import SwiftUI
import UIKit

struct NativeSearchBar: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UISearchBar {
        let searchBar = UISearchBar()
        searchBar.delegate = context.coordinator
        searchBar.searchBarStyle = .minimal
        searchBar.placeholder = L10n.string("ui.search.prompt")
        searchBar.autocapitalizationType = .none
        searchBar.autocorrectionType = .no
        searchBar.returnKeyType = .search
        searchBar.enablesReturnKeyAutomatically = true
        searchBar.searchTextField.adjustsFontForContentSizeCategory = true
        searchBar.searchTextField.accessibilityIdentifier = "native-search-field"
        return searchBar
    }

    func updateUIView(_ searchBar: UISearchBar, context: Context) {
        context.coordinator.parent = self
        searchBar.placeholder = L10n.string("ui.search.prompt")
        if searchBar.text != text {
            searchBar.text = text
        }
        if searchBar.showsCancelButton != isFocused {
            searchBar.setShowsCancelButton(isFocused, animated: true)
        }
        if !isFocused, searchBar.searchTextField.isFirstResponder {
            searchBar.resignFirstResponder()
        }
    }

    final class Coordinator: NSObject, UISearchBarDelegate {
        var parent: NativeSearchBar

        init(_ parent: NativeSearchBar) {
            self.parent = parent
        }

        func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
            parent.text = searchText
        }

        func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
            if !parent.isFocused {
                parent.isFocused = true
            }
        }

        func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
            if parent.isFocused {
                parent.isFocused = false
            }
        }

        func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
            searchBar.resignFirstResponder()
            parent.isFocused = false
        }

        func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
            searchBar.resignFirstResponder()
            parent.text = ""
            parent.isFocused = false
        }
    }
}
