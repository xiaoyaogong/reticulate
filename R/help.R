
#' Register help topics
#'
#' Register a set of help topics for dispatching from F1 help
#'
#' @param type Type (module or class)
#' @param topics Named list of topics
#'
#' @keywords internal
#' @export
register_help_topics <- function(type = c("module", "class"), topics) {

  # pick the right environment for this type
  type <- match.arg(type)
  envir <- switch(type,
                  module = .module_help_topics,
                  class = .class_help_topics
  )

  # assign the list into the environment
  for (name in names(topics))
    assign(name, topics[[name]], envir = envir)
}

# Generic help_handler returned from .DollarNames -- dispatches to various
# other help handler functions
help_handler <- function(type = c("completion", "parameter", "url"), topic, source, ...) {
  type <- match.arg(type)
  if (type == "completion") {
    help_completion_handler.python.builtin.object(topic, source)
  } else if (type == "parameter") {
    help_completion_parameter_handler.python.builtin.object(source)
  } else if (type == "url") {
    help_url_handler.python.builtin.object(topic, source)
  }
}

# Return help for display in the completion popup window
help_completion_handler.python.builtin.object <- function(topic, source) {

  if (!py_available(initialize = FALSE))
    return(NULL)

  # convert source to object if necessary
  source <- source_as_object(source)
  if (is.null(source))
    return(NULL)

  # check for property help
  help <- import("rpytools.help")
  description <- help$get_property_doc(source, topic)
  # check for standard help
  if (is.null(description)) {
    inspect <- import("inspect")
    description <- inspect$getdoc(help_get_attribute(source, topic))
  }
  # default to no description
  if (is.null(description))
    description <- ""
  matches <- regexpr(pattern ='\n', description, fixed=TRUE)
  if (matches[[1]] != -1)
    description <- substring(description, 1, matches[[1]])
  description <- convert_description_types(description)

  # try to generate a signature
  signature <- NULL
  target <- help_get_attribute(source, topic)
  if (!is.null(target) && py_is_callable(target)) {
    help <- import("rpytools.help")
    signature <- help$generate_signature_for_function(target)
    if (is.null(signature))
      signature <- "()"
    signature <- paste0(topic, signature)
  }

  # return docs
  list(title = topic,
       signature = signature,
       description = description)
}


# Return parameter help for display in the completion popup window
help_completion_parameter_handler.python.builtin.object <- function(source) {

  if (!py_available(initialize = FALSE))
    return(NULL)

  # split into topic and source
  components <- source_components(source)
  if (is.null(components))
    return(NULL)
  topic <- components$topic
  source <- components$source

  # get the function
  target <- help_get_attribute(source, topic)
  if (!is.null(target) & py_is_callable(target)) {
    help <- import("rpytools.help")
    args <- help$get_arguments(target)
    if (!is.null(args)) {
      # get the descriptions
      doc <- help$get_doc(target)
      if (is.null(doc))
        arg_descriptions <- args
      else
        arg_descriptions <- arg_descriptions_from_doc(args, doc)
      return(list(
        args = args,
        arg_descriptions = arg_descriptions
      ))
    }
  }

  # no parameter help found
  NULL
}


# Handle requests for external (F1) help
help_url_handler.python.builtin.object <- function(topic, source) {

  if (!py_available(initialize = FALSE))
    return(NULL)

  # normalize topic and source for various calling scenarios
  if (grepl(" = $", topic)) {
    components <- source_components(source)
    if (is.null(components))
      return(NULL)
    topic <- components$topic
    source <- components$source
  } else {
    source <- source_as_object(source)
    if (is.null(source))
      return(NULL)
  }

  # get help page
  page <- NULL
  inspect <- import("inspect")
  if (inspect$ismodule(source)) {
    module <- paste(source$`__name__`)
    help <- module_help(module, topic)
  } else {
    help <- class_help(class(source), topic)
  }

  # return help (can be "")
  help
}


# Handle requests for the list of arguments for a function
help_formals_handler.python.builtin.object <- function(topic, source) {

  if (!py_available(initialize = FALSE))
    return(NULL)

  # check for module proxy
  if (py_is_module_proxy(source))
    return(NULL)
  
  if (py_has_attr(source, topic)) {
    target <- help_get_attribute(source, topic)
    if (!is.null(target) && py_is_callable(target)) {
      help <- import("rpytools.help")
      args <- help$get_arguments(target)
      if (!is.null(args)) {
        return(list(
          formals = args,
          helpHandler = "reticulate:::help_handler"
        ))
      }
    }
  }

  # default to NULL if we couldn't get the arguments
  NULL
}

# Extract argument descriptions from python docstring
arg_descriptions_from_doc <- function(args, doc) {
  doc <- strsplit(doc, "\n", fixed = TRUE)[[1]]
  arg_descriptions <- sapply(args, function(arg) {
    prefix <- paste0("  ", arg, ": ")
    arg_line <- which(grepl(paste0("^", prefix), doc))
    if (length(arg_line) > 0) {
      arg_description <- substring(doc[[arg_line]], nchar(prefix))
      next_line <- arg_line + 1
      while((arg_line + 1) <= length(doc)) {
        line <- doc[[arg_line + 1]]
        if (grepl("^    ", line)) {
          arg_description <- paste(arg_description, line)
          arg_line <- arg_line + 1
        }
        else
          break
      }
      arg_description <- gsub("^\\s*", "", arg_description)
      arg_description <- convert_description_types(arg_description)
    } else {
      arg
    }
  })
  arg_descriptions
}

# Convert types in description
convert_description_types <- function(description) {
  description <- sub("`None`", "`NULL`", description)
  description <- sub("`True`", "`TRUE`", description)
  description <- sub("`False`", "`FALSE`", description)
  description
}

# Convert source to object if necessary
source_as_object <- function(source) {

  if (is.character(source)) {
    source <- tryCatch(eval(parse(text = source), envir = globalenv()),
                       error = function(e) NULL)
    if (is.null(source))
      return(NULL)
  }

  source
}

# Split source string into source and topic
source_components <- function(source) {
  components <- strsplit(source, "\\$")[[1]]
  topic <- components[[length(components)]]
  source <- paste(components[1:(length(components)-1)], collapse = "$")
  source <- source_as_object(source)
  if (!is.null(source))
    list(topic = topic, source = source)
  else
    NULL
}


module_help <- function(module, topic) {

  # do we have a page for this module/topic?
  lookup <- paste(module, topic, sep = ".")
  page <- .module_help_topics[[lookup]]

  # if so then append topic
  if (!is.null(page))
    paste(page, topic, sep = "#")
  else
    ""
}

class_help <- function(class, topic) {

  # call recursively for more than one class
  if (length(class) > 1) {
    # call for each class
    for (i in 1:length(class)) {
      help <- class_help(class[[i]], topic)
      if (nzchar(help))
        return(help)
    }
    # no help found
    return("")
  }

  # do we have a page for this class?
  page <- .class_help_topics[[class]]

  # if so then append class and topic
  if (!is.null(page)) {
    components <- strsplit(class, ".", fixed = TRUE)[[1]]
    class <- components[[length(components)]]
    paste0(page, "#", class, ".", topic)
  } else {
    ""
  }
}

help_get_attribute <- function(source, topic) {

  # check for module proxy
  if (py_is_module_proxy(source))
    return(NULL)
  
  # check for sub-module
  if (py_is_module(source) && !py_has_attr(source, topic)) {
    module <- py_get_submodule(source, topic)
    if (!is.null(module))
      return(module)
  }

  # get attribute w/ no warnings or errors
  tryCatch(py_suppress_warnings(py_get_attr(source, topic)), error = function(e) NULL)
}

# Environments where we store help topics (mappings of module/class name to URL)
.module_help_topics <- new.env(parent = emptyenv())
.class_help_topics <- new.env(parent = emptyenv())





