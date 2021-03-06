#' @import dplyr
#' @import RMySQL
NULL

#' @export
dplyr::src_mysql

#' Read environment variables MYSQL_(DBNAME|HOST|PORT|USER|PASSWORD)
#'     and connect to corresponding database.
#'
#' @export
db_from_env <- function() {
    keys <- c("dbname", "host", "port", "user", "password")
    values <- lapply(keys, function(x) Sys.getenv(paste0("MYSQL_", toupper(x))))
    names(values) <- keys
    values$port <- as.integer(values$port)
    my_db <- do.call(src_mysql, values)
    return(my_db)
}

#' @importFrom DBI dbGetQuery
#' @importFrom utils str
describe_database <- function(db) {
    table_names <- dbGetQuery(db$con, "show tables")[, 1]
    tables <- lapply(table_names, function(x) get_tbl(db, x))

    for (i in 1:length(table_names)) {
        x <- table_names[i]
        data <- tables[[i]]

        if (nrow(data) > 0) {
            print(x)
            str(data)
            cat("\n")
        }
    }
}

get_tbl <- function(...) suppressWarnings(tbl(...) %>% as.data.frame())

remove_empty_columns <- function(x) {
    for (k in names(x)) {
        if (all(is.na(x[, k]))) {
            x[[k]] <- NULL
        }
    }
    return(x)
}

#' Retrieve and clean a table of actions from the passed database.
#'
#' @param db Database to pull actions from.
#' @param table_prefix Pull data from
#'     {{table_prefix}}log_link_visit_action and
#'     {{table_prefix}}log_action.
#'
#' @importFrom lubridate ymd_hms floor_date
#' @importFrom utils read.csv
#' @importFrom tidyr separate_
#' @export
get_actions <- function(db, table_prefix = "piwik_") {
    actions <- get_tbl(db, paste0(table_prefix, "log_link_visit_action"))

    actions <- remove_empty_columns(actions)

    ## Set up metadata on action types
    action_types <- get_tbl(db, paste0(table_prefix, "log_action"))
    path <- system.file("extdata", "action_types.csv", package = "piwikr")
    metadata <- read.csv(path)
    action_types <- action_types %>%
        left_join(metadata, by = c("type" = "id")) %>%
        select_("idaction", "name", "category_name")

    ## Merge action types back into actions
    actions <- actions %>%
        left_join(action_types, by = c("idaction_url" = "idaction"))
    actions$idaction_name <- NULL
    actions$idaction_url <- NULL

    ## custom_float: an unspecified float field, usually used to hold
    ## the time it took the server to serve this action
    actions <- actions %>% select_(
        id = "idlink_va",
        visitor_id = "idvisitor",
        visit_id = "idvisit",
        datetime = "server_time",
        url = "name",
        type = "category_name",
        time_to_serve = "custom_float",
        time_spent_on_previous_action = "time_spent_ref_action"
        ) %>%
        mutate_(datetime = ~ ymd_hms(datetime)) %>%
        mutate_(day = ~ floor_date(datetime, "day"))

    ## Clean up url column
    actions <- actions %>%
        separate_(col = "url", into = c("url", "query_string"), sep = "[?]", fill = "right")

    return(actions)
}

#' Retrieve and clean a table of visits from the passed database.
#'
#' @param db Database to pull actions from.
#' @param table_prefix Pull data from {{table_prefix}}log_visit.
#'
#' @importFrom lubridate ymd_hms
#' @importFrom tidyr separate_
#' @export
get_visits <- function(db, table_prefix = "piwik_") {
    visits <- get_tbl(db, paste0(table_prefix, "log_visit"))
    visits <- remove_empty_columns(visits)

    visits$visit_first_action_time <- ymd_hms(visits$visit_first_action_time)

    visits <- visits %>%
        separate_(
            "config_resolution", c("screen_width", "screen_height"), sep = "x",
            convert = TRUE, fill = "right"
        )
    return(visits)
}
