// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.

import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
// import {hooks as colocatedHooks} from "phoenix-colocated/mr_munch_me_accounting_app"
const colocatedHooks = {}
import topbar from "../vendor/topbar"

// Heroicons
// import "../vendor/heroicons"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// Handle hash-based scrolling after page load
const scrollToHash = () => {
  if (window.location.hash) {
    const element = document.querySelector(window.location.hash)
    if (element) {
      setTimeout(() => {
        element.scrollIntoView({ behavior: "smooth", block: "start" })
      }, 100)
    }
  }
}

// Handle scrolling for regular page loads
window.addEventListener("load", scrollToHash)

// Handle scrolling for LiveView navigation
window.addEventListener("phx:page-loading-stop", scrollToHash)

// Dropdown menu toggle functionality
window.toggleDropdown = function(button) {
  const dropdown = button.closest('.nav-dropdown')
  const menu = dropdown.querySelector('.nav-dropdown-menu')
  const icon = button.querySelector('.dropdown-icon')
  
  dropdown.classList.toggle('is-open')
  
  if (dropdown.classList.contains('is-open')) {
    menu.style.maxHeight = menu.scrollHeight + 'px'
    icon.style.transform = 'rotate(180deg)'
  } else {
    menu.style.maxHeight = '0'
    icon.style.transform = 'rotate(0deg)'
  }
}

// Initialize dropdowns on page load
window.addEventListener('load', () => {
  const dropdowns = document.querySelectorAll('.nav-dropdown')
  dropdowns.forEach(dropdown => {
    const menu = dropdown.querySelector('.nav-dropdown-menu')
    const icon = dropdown.querySelector('.dropdown-icon')
    // Open only dropdowns with data-default-open="true"
    const shouldBeOpen = dropdown.getAttribute('data-default-open') === 'true'
    if (shouldBeOpen) {
      dropdown.classList.add('is-open')
      menu.style.maxHeight = menu.scrollHeight + 'px'
      if (icon) {
        icon.style.transform = 'rotate(180deg)'
      }
    } else {
      dropdown.classList.remove('is-open')
      menu.style.maxHeight = '0'
      if (icon) {
        icon.style.transform = 'rotate(0deg)'
      }
    }
  })
})

// Re-initialize dropdowns after LiveView navigation
window.addEventListener('phx:page-loading-stop', () => {
  const dropdowns = document.querySelectorAll('.nav-dropdown')
  dropdowns.forEach(dropdown => {
    const menu = dropdown.querySelector('.nav-dropdown-menu')
    const icon = dropdown.querySelector('.dropdown-icon')
    // Preserve open/closed state after navigation
    if (dropdown.classList.contains('is-open')) {
      menu.style.maxHeight = menu.scrollHeight + 'px'
      if (icon) {
        icon.style.transform = 'rotate(180deg)'
      }
    } else {
      menu.style.maxHeight = '0'
      if (icon) {
        icon.style.transform = 'rotate(0deg)'
      }
    }
  })
})

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

