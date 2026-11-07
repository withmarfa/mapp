import Foundation

/// How the app's scripts read a document they did not write.
///
/// A document can name its elements after the properties of the objects around them: a form's controls, and a
/// document's images, objects and frames, answer to their `name` (and some to their `id`) before the built-in property
/// of that name does. So `<img name="cloneNode">` makes `document.cloneNode` an image, and a control named `children`
/// makes `form.children` that control, which can put an element inside its own descendants. A script that asks the
/// document for a property can be sent anywhere, or into a loop that never ends.
///
/// The prelude takes each method and getter the scripts use from the prototype once, before any of the document's names
/// can reach it, and the scripts then call those through `dom`. The scripts run in a world of their own
/// (`SealedWebPage.world`), whose prototypes the document cannot change; a document's own scripts cannot either.
nonisolated enum SafeDOM {
    /// Defines `dom` for a script. Every function takes the node first: `dom.getAttribute(e, 'href')`.
    static let script = """
        const dom = (() => {
          const call = Function.prototype.call;
          const getter = (type, name) => call.bind(Object.getOwnPropertyDescriptor(type.prototype, name).get);
          const method = (type, name) => call.bind(type.prototype[name]);
          return Object.freeze({
            body: getter(Document, 'body'),
            head: getter(Document, 'head'),
            documentElement: getter(Document, 'documentElement'),
            createElement: method(Document, 'createElement'),
            createRange: method(Document, 'createRange'),
            createTreeWalker: method(Document, 'createTreeWalker'),
            queryAllInDocument: method(Document, 'querySelectorAll'),
            queryInDocument: method(Document, 'querySelector'),
            queryAll: method(Element, 'querySelectorAll'),
            query: method(Element, 'querySelector'),
            matches: method(Element, 'matches'),
            closest: method(Element, 'closest'),
            getAttribute: method(Element, 'getAttribute'),
            getAttributeNames: method(Element, 'getAttributeNames'),
            setAttribute: method(Element, 'setAttribute'),
            removeAttribute: method(Element, 'removeAttribute'),
            append: method(Element, 'append'),
            remove: method(Element, 'remove'),
            replaceWith: method(Element, 'replaceWith'),
            classList: getter(Element, 'classList'),
            innerHTML: getter(Element, 'innerHTML'),
            localName: getter(Element, 'localName'),
            previousElementSibling: getter(Element, 'previousElementSibling'),
            nextElementSibling: getter(Element, 'nextElementSibling'),
            style: getter(HTMLElement, 'style'),
            cloneNode: method(Node, 'cloneNode'),
            contains: method(Node, 'contains'),
            parentElement: getter(Node, 'parentElement'),
            parentNode: getter(Node, 'parentNode'),
            childNodes: getter(Node, 'childNodes'),
            nodeType: getter(Node, 'nodeType'),
            nodeValue: getter(Node, 'nodeValue'),
            ownerDocument: getter(Node, 'ownerDocument'),
            textContent: getter(Node, 'textContent'),
          });
        })();
        """
}
