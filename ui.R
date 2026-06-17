if (exists("ensure_r_tempdir", mode = "function")) ensure_r_tempdir()

library(shiny)
library(DT)

shinyUI(fluidPage(
  tags$head(
    tags$title("Find Eurostat dataset(s)"),
    tags$link(rel = "icon", type = "image/x-icon", href = "https://cdn-icons-png.flaticon.com/512/541/541415.png"),
    tags$style(HTML("
      .find-estat-spinner-overlay {
        align-items: center;
        background: rgba(255, 255, 255, 0.45);
        bottom: 0;
        display: none;
        justify-content: center;
        left: 0;
        pointer-events: auto;
        position: fixed;
        right: 0;
        top: 0;
        z-index: 99999;
      }

      .find-estat-spinner {
        animation: find-estat-spin 0.85s linear infinite;
        border: 8px solid #e6e6e6;
        border-radius: 50%;
        border-top-color: #b8b8b8;
        height: 72px;
        width: 72px;
      }

      @keyframes find-estat-spin {
        to { transform: rotate(360deg); }
      }
    ")),
    tags$script(HTML("
      (function() {
        var searchIds = ['keyword', 'keyword2', 'keyword3'];

        function fieldValue(id) {
          var el = document.getElementById(id);
          return el ? el.value : '';
        }

        function hasSearchText(payload) {
          return searchIds.some(function(id) {
            return (payload[id] || '').trim().length > 0;
          });
        }

        function setSpinner(show) {
          var el = document.getElementById('find_estat_spinner_overlay');
          if (!el) return;
          el.style.display = show ? 'flex' : 'none';
          el.setAttribute('aria-hidden', show ? 'false' : 'true');
        }

        function submitSearch() {
          if (!window.Shiny || !Shiny.setInputValue) return;
          var payload = {
            keyword: fieldValue('keyword'),
            keyword2: fieldValue('keyword2'),
            keyword3: fieldValue('keyword3'),
            nonce: Date.now() + Math.random()
          };
          setSpinner(hasSearchText(payload));
          Shiny.setInputValue('searchCriteria', payload, {priority: 'event'});
        }

        var spinnerHandlerRegistered = false;

        function registerSpinnerHandler() {
          if (spinnerHandlerRegistered || !window.Shiny || !Shiny.addCustomMessageHandler) return;
          spinnerHandlerRegistered = true;
          Shiny.addCustomMessageHandler('findEstatSpinner', function(message) {
            setSpinner(message && message.show);
          });
        }

        registerSpinnerHandler();
        document.addEventListener('DOMContentLoaded', registerSpinnerHandler);
        window.setTimeout(registerSpinnerHandler, 0);
        window.setTimeout(registerSpinnerHandler, 500);

        if (window.jQuery) {
          jQuery(document).on('shiny:connected', registerSpinnerHandler);
          jQuery(document).on('shiny:disconnected', function() {
            setSpinner(false);
          });
        }

        window.addEventListener('pageshow', function() {
          setSpinner(false);
        });

        document.addEventListener('click', function(event) {
          var target = event.target;
          if (!target || !target.closest || !target.closest('#update_view')) return;
          event.preventDefault();
          submitSearch();
        });

        document.addEventListener('keydown', function(event) {
          var target = event.target;
          var isSearchInput = target && target.matches && target.matches('#keyword, #keyword2, #keyword3');
          var isEnter = event.key === 'Enter' || event.keyCode === 13 || event.which === 13;
          if (!isSearchInput || !isEnter) return;

          event.preventDefault();
          target.dispatchEvent(new Event('input', {bubbles: true}));
          target.dispatchEvent(new Event('change', {bubbles: true}));
          submitSearch();
        });
      })();
    "))
  ),

  tags$div(
    id = "find_estat_spinner_overlay",
    class = "find-estat-spinner-overlay",
    role = "status",
    `aria-live` = "polite",
    `aria-label` = "Loading",
    `aria-hidden` = "true",
    tags$div(class = "find-estat-spinner")
  ),

  h3("Find Eurostat dataset(s)"),

  fluidRow(
    column(
      width = 6,
      p(
        "Powered by ",
        tags$a("R", href = "https://www.r-project.org/", target = "_blank", rel = "noopener noreferrer"),
        " / ",
        tags$a("Shiny", href = "https://shiny.posit.co/", target = "_blank", rel = "noopener noreferrer")
      )
    )
  ),

  h5("Multiple keywords separated by spaces can be used. Upper and lower case difference is ignored."),
  h5(HTML('If more than one input box is filled in, they are all interpreted with <a href="https://en.wikipedia.org/wiki/Logical_conjunction" target="_blank">logical AND</a>.')),

  fluidRow(
    column(
      3,
      textInput(
        "keyword",
        HTML('Search keyword(s), <a href="https://en.wikipedia.org/wiki/Logical_conjunction" target="_blank">logical AND</a>, across <b>the whole data group tree, dataset names, and codes</b>:')
      )
    ),
    column(
      3,
      textInput(
        "keyword2",
        HTML('Search keyword(s), <a href="https://en.wikipedia.org/wiki/Logical_disjunction" target="_blank">logical OR</a>, across <b>dataset/table codes</b>:<br><br>')
      )
    ),
    column(
      3,
      textInput(
        "keyword3",
        HTML('<i><b>Exclude</b></i> keyword(s), <a href="https://en.wikipedia.org/wiki/Logical_disjunction" target="_blank">logical OR</a>, across <b>the whole data group tree, dataset names, and codes</b>:')
      )
    ),
    column(
      1,
      helpText(" "),
      tags$button(
        id = "update_view",
        type = "button",
        class = "btn btn-primary",
        HTML("<br>Update View<br><br>")
      )
    ),
    column(2, helpText("Download search results:"), downloadButton("downloadData", "Download"))
  ),

  hr(),
  div(uiOutput("results"), style = "font-size:85%")
))
