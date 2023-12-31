.edit <- function(book, path, open) {
    f <- file.path(path(book), path)
    if (rlang::is_interactive() && open) usethis::edit_file(f)
    else usethis::ui_todo("Edit {usethis::ui_path(f)}")
    invisible(book)
}

#' @rdname BiocBook-editing
#' @export 

edit_yml <- function(book, yml = c('_book', '_website', '_knitr', '_format'), open = TRUE) {
    yml <- match.arg(yml)
    .edit(book, file.path("inst", "assets", paste0(yml, ".yml")), open = open)
}

#' @rdname BiocBook-editing
#' @export 

edit_bib <- function(book, open = TRUE) {
    .edit(book, file.path("inst", "assets", "bibliography.bib"), open = open)
}

#' @rdname BiocBook-editing
#' @export 

edit_requirements_yml <- function(book, open = TRUE) {
    .edit(book, file.path("inst", "requirements"), open = open)
}

#' @rdname BiocBook-editing
#' @export 

edit_css <- function(book, open = TRUE) {
    .edit(book, file.path("inst", "assets", "book.scss"), open = open)
}

#' @rdname BiocBook-editing
#' @export 

preview <- function(book, browse = FALSE, watch = FALSE) {

    check_deps(book)
    quarto::quarto_preview(file.path(path(book), 'inst'), browse = browse, watch = watch)

}

#' @rdname BiocBook-editing
#' @export 

publish <- function(book, message = "Publishing") {

    f <- gert::git_status(repo = path(book), pathspec = 'inst/')
    f <- f[!f$staged, ]
    if (nrow(f) == 0) cli::cli_abort(
        "No files to stage."
    )
    staged <- gert::git_add(files = f$file, repo = path(book))
    cli::cli_alert_success(cli::col_grey("Staged {nrow(staged)} updated/new file(s)"))
    hash <- gert::git_commit(message = message, repo = path(book))
    cli::cli_alert_success(paste0(
        cli::col_grey("Committed all staged files"), 
        " [commit: ", 
        cli::col_cyan(stringr::str_trunc(hash, 7, ellipsis = '')), 
        "]"
    ))
    gert::git_push(repo = path(book))
    cli::cli_alert_success(paste0(
        cli::col_grey("Pushed to Github"), 
        " [remote: ", 
        cli::col_cyan(book@remote_repository), 
        "]"
    ))

    invisible(TRUE)
}

#' @rdname BiocBook-editing
#' @export

status <- function(book) {
    purrr::map_dfr(releases(book), function(release) {

        GH_api <- "https://api.github.com"
        PAT <- gitcreds::gitcreds_get()$password
        gh_creds <- gh::gh_whoami(.token = PAT)
        user <- gh_creds$login
        headers <- httr::add_headers(
            Accept = "application/vnd.github+json", 
            Authorization = glue::glue("Bearer {PAT}"), 
            "X-GitHub-Api-Version" = "2022-11-28"
        )
        repo <- basename(book@remote_repository) |> tools::file_path_sans_ext()
        runs <- httr::GET(
            glue::glue("{GH_api}/repos/{user}/{repo}/actions/runs"), 
            headers, 
            query = list(branch = release), 
            encode = 'json'
        ) |> httr::content() |> 
            purrr::pluck(2) |>
            purrr::map_dfr(~ {tibble::tibble(
            branch = .x$head_branch, 
            id = .x$id, 
            commit = .x$head_sha, 
            commit_message = .x$display_title, 
            completed_at = .x$completed_at, 
            status = .x$status, 
            conclusion = .x$conclusion
        )})
        jobs_latest_run <- httr::GET(
            glue::glue("{GH_api}/repos/{user}/{repo}/actions/runs/{runs[1, ][['id']]}/jobs"), 
            headers, 
            encode = 'json'
        ) 
        purrr::map_dfr(httr::content(jobs_latest_run)[[2]], ~ {tibble::tibble(
            branch = .x$head_branch, 
            name = dplyr::case_when(grepl("^Build and push", .x$name) ~ "Docker image", grepl("^Render and publish", .x$name) ~ "Website", .default = "Other"), 
            conclusion = .x$conclusion, 
            commit = .x$head_sha, 
            completed_at = .x$completed_at
        )})

    })
}
