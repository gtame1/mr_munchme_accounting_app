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
import topbar from "../vendor/topbar"
import TomSelect from "../vendor/tom-select.min.js"
import Chart from "../vendor/chart.umd.min.js"

// ==============================
// LiveView Hooks
// ==============================

const SearchableSelect = {
  mounted() {
    this.initTomSelect()
  },

  updated() {
    // Destroy and reinitialize if options have changed
    if (this.tomSelect) {
      this.tomSelect.destroy()
    }
    this.initTomSelect()
  },

  destroyed() {
    if (this.tomSelect) {
      this.tomSelect.destroy()
    }
  },

  initTomSelect() {
    const select = this.el.querySelector('select')
    if (!select) return

    const prompt = select.dataset.prompt || 'Search...'

    this.tomSelect = new TomSelect(select, {
      create: false,
      sortField: {
        field: "text",
        direction: "asc"
      },
      placeholder: prompt,
      allowEmptyOption: true,
      controlInput: '<input>',
      render: {
        option: function(data, escape) {
          return '<div class="option">' + escape(data.text) + '</div>'
        },
        item: function(data, escape) {
          return '<div class="item">' + escape(data.text) + '</div>'
        },
        no_results: function(data, escape) {
          return '<div class="no-results">No results found</div>'
        }
      }
    })
  }
}

// Chart colors matching bakery theme
const chartColors = {
  primary: '#8a3b2f',
  primarySoft: '#fbe4db',
  revenue: '#059669',
  expense: '#dc2626',
  neutral: '#8b6f5b',
  background: '#fff7f2',
  netPositive: '#059669',
  netNegative: '#dc2626'
}

const BarChart = {
  mounted() {
    this.initChart()
  },

  updated() {
    if (this.chart) {
      this.chart.destroy()
    }
    this.initChart()
  },

  destroyed() {
    if (this.chart) {
      this.chart.destroy()
    }
  },

  initChart() {
    const canvas = this.el.querySelector('canvas')
    if (!canvas) return

    const dataAttr = canvas.dataset.chartData
    if (!dataAttr) return

    let data
    try {
      data = JSON.parse(dataAttr)
    } catch (e) {
      console.error('Invalid chart data:', e)
      return
    }

    const ctx = canvas.getContext('2d')

    this.chart = new Chart(ctx, {
      type: 'bar',
      data: {
        labels: data.labels || [],
        datasets: data.datasets || []
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: {
            position: 'top',
            labels: {
              usePointStyle: true,
              padding: 20,
              font: {
                family: 'system-ui, -apple-system, sans-serif',
                size: 12
              }
            }
          },
          tooltip: {
            backgroundColor: '#3d2318',
            titleFont: { family: 'system-ui', size: 13 },
            bodyFont: { family: 'system-ui', size: 12 },
            padding: 12,
            cornerRadius: 8,
            callbacks: {
              label: function(context) {
                let value = context.raw
                // Format as currency (divide by 100 to convert cents to pesos)
                const formatted = (value / 100).toLocaleString('es-MX', {
                  style: 'currency',
                  currency: 'MXN'
                })
                return context.dataset.label + ': ' + formatted
              }
            }
          }
        },
        scales: {
          x: {
            grid: {
              display: false
            },
            ticks: {
              font: {
                family: 'system-ui',
                size: 11
              }
            }
          },
          y: {
            beginAtZero: true,
            grid: {
              color: 'rgba(139, 111, 91, 0.1)'
            },
            ticks: {
              font: {
                family: 'system-ui',
                size: 11
              },
              callback: function(value) {
                return '$' + (value / 100).toLocaleString('es-MX')
              }
            }
          }
        }
      }
    })
  }
}

const DoughnutChart = {
  mounted() {
    this.initChart()
  },

  updated() {
    if (this.chart) {
      this.chart.destroy()
    }
    this.initChart()
  },

  destroyed() {
    if (this.chart) {
      this.chart.destroy()
    }
  },

  initChart() {
    const canvas = this.el.querySelector('canvas')
    if (!canvas) return

    const dataAttr = canvas.dataset.chartData
    if (!dataAttr) return

    let data
    try {
      data = JSON.parse(dataAttr)
    } catch (e) {
      console.error('Invalid chart data:', e)
      return
    }

    const ctx = canvas.getContext('2d')

    this.chart = new Chart(ctx, {
      type: 'doughnut',
      data: {
        labels: data.labels || [],
        datasets: data.datasets || []
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: {
            position: 'right',
            labels: {
              usePointStyle: true,
              padding: 15,
              font: {
                family: 'system-ui, -apple-system, sans-serif',
                size: 12
              }
            }
          },
          tooltip: {
            backgroundColor: '#3d2318',
            titleFont: { family: 'system-ui', size: 13 },
            bodyFont: { family: 'system-ui', size: 12 },
            padding: 12,
            cornerRadius: 8,
            callbacks: {
              label: function(context) {
                let value = context.raw
                const formatted = (value / 100).toLocaleString('es-MX', {
                  style: 'currency',
                  currency: 'MXN'
                })
                return context.label + ': ' + formatted
              }
            }
          }
        }
      }
    })
  }
}

const colocatedHooks = {
  SearchableSelect,
  BarChart,
  DoughnutChart
}

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

// Initialize dropdowns without animation
const initializeDropdowns = () => {
  const dropdowns = document.querySelectorAll('.nav-dropdown')
  dropdowns.forEach(dropdown => {
    const menu = dropdown.querySelector('.nav-dropdown-menu')
    const icon = dropdown.querySelector('.dropdown-icon')
    
    // Disable transitions during initialization
    menu.classList.add('no-transition')
    if (icon) {
      icon.style.transition = 'none'
    }
    
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
    
    // Re-enable transitions after styles are set
    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        menu.classList.remove('no-transition')
        if (icon) {
          icon.style.transition = ''
        }
      })
    })
  })
}

// Initialize dropdowns on page load
window.addEventListener('load', initializeDropdowns)

// Re-initialize dropdowns after LiveView navigation (without animation)
window.addEventListener('phx:page-loading-stop', initializeDropdowns)

// ==============================
// Mobile Hamburger Menu
// ==============================

const initHamburgerMenu = () => {
  const hamburgerBtn = document.getElementById('hamburger-btn')
  const sidebar = document.getElementById('sidebar')
  const overlay = document.getElementById('sidebar-overlay')

  if (!hamburgerBtn || !sidebar || !overlay) return

  const toggleMenu = (open) => {
    const isOpen = open !== undefined ? open : !sidebar.classList.contains('is-open')
    sidebar.classList.toggle('is-open', isOpen)
    overlay.classList.toggle('is-open', isOpen)
    hamburgerBtn.setAttribute('aria-expanded', isOpen)

    // Prevent body scroll when menu is open
    document.body.style.overflow = isOpen ? 'hidden' : ''
  }

  // Toggle on hamburger click
  hamburgerBtn.addEventListener('click', (e) => {
    e.stopPropagation()
    toggleMenu()
  })

  // Close on overlay click
  overlay.addEventListener('click', () => toggleMenu(false))

  // Close menu when a nav link is clicked
  sidebar.querySelectorAll('.nav-link').forEach(link => {
    link.addEventListener('click', () => toggleMenu(false))
  })

  // Close on escape key
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && sidebar.classList.contains('is-open')) {
      toggleMenu(false)
    }
  })
}

// Initialize hamburger menu on page load
window.addEventListener('load', initHamburgerMenu)

// Re-initialize after LiveView navigation
window.addEventListener('phx:page-loading-stop', initHamburgerMenu)

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

