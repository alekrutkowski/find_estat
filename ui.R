library(shiny)
library(DT)

shinyUI(fluidPage(
  tags$head(
    tags$title("Find Eurostat dataset(s)"),
    tags$link(rel = "icon", type = "image/x-icon", href = "https://cdn-icons-png.flaticon.com/512/541/541415.png")
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
  h5("If more than one input box is filled in, they are all interpreted with logical AND."),

  fluidRow(
    column(
      3,
      textInput(
        "keyword",
        HTML("Search keyword(s), logical AND, across <b>the whole data group tree, dataset names, and codes</b>:")
      )
    ),
    column(
      3,
      textInput(
        "keyword2",
        HTML("Search keyword(s), logical OR, across <b>dataset/table codes</b>:<br><br>")
      )
    ),
    column(
      3,
      textInput(
        "keyword3",
        HTML("<b>Exclude</b> keyword(s), logical OR, across <b>the whole data group tree, dataset names, and codes</b>:")
      )
    ),
    column(1, helpText(" "), submitButton(HTML("<br>Update View<br><br>"))),
    column(2, helpText("Download search results:"), downloadButton("downloadData", "Download"))
  ),

  hr(),
  div(uiOutput("results"), style = "font-size:85%")
))
