## read CSV-formatted data into an R data frame

## arguments
##       file  character vector naming one or more CSV files to read
##   order.by  list of variables to sort the resulting data frame
##   add.user  add user variable based on numeric part of file name
##        lag  time lag adjustment for calculating dates from date-times
##        ...  additional arguments passed to read.csv

read.data <- function(file, order.by = NULL, add.user = FALSE, ...) {
  ## read named files into a list of data frames
  d <- lapply(file, read.csv, header = TRUE, strip.white = TRUE, ...)
  ## make each data frame contain the the same variables in the same order;
  ## if one such variable does not appear in a given data frame, add it as a
  ## vector of missing values
  if (length(d) > 1) {
    l <- d
    n <- unique(unlist(lapply(d, names)))
    d <- lapply(l, function(x) data.frame(matrix(NA, nrow(x), length(n),
                                                 dimnames = list(NULL, n))))
    sapply(1:length(l), function(i) d[[i]][, match(names(l[[i]]), n)] <<- l[[i]])
    if (add.user)
      d <- mapply(function(x, y) data.frame(test.id = x, y),
                  as.numeric(gsub("[^0-9]*([0-9]+)[^0-9]*", "\\1", file)), d,
                  SIMPLIFY = FALSE)
  }
  ## append, row-wise, the list of data frames to one another
  d <- do.call("rbind", d)
  ## normalize variable names
  names(d) <- tolower(names(d))
  names(d) <- gsub("_", ".", names(d))
  names(d) <- gsub("\\.$", "", names(d))
  names(d)[grep("^(user|id)$", names(d))[1]] <- "userid"
  names(d)[names(d) == "last.updated"] <- "time.updated"
  names(d)[names(d) == "test.id"] <- "user"
  ## omit extraneous variables
  d <- d[, which(!grepl("^(key|(first|last|variable)\\.name|x|x\\.[0-9]+)$",
                        names(d))), drop = FALSE]
  ## keep only pilot users and isolate their participant number
  if ("userid" %in% names(d)) {
    d <- subset(d, grepl("heartsteps.test[0-9]+", userid))
    d$user <- as.numeric(gsub("(heartsteps\\.test|@gmail.*$)", "", d$userid))
  }
  ## convert variables that should be numeric, apart from missing values
  l <- which(names(d) %in% c("distance", "snow", "temperature"))
  if (length(l)) {
    d[, l][d[, l] == "unknown"] <- NA
    d[, l] <- sapply(l, function(x) as.numeric(d[, x]))
  }
  ## indicate character date-time variables representing by name
  ## (e.g. 'time.finished', 'time.started', 'time.stamp', 'time.updated', ...)
  l <- which(grepl("(^time\\.(fin|sta|up)|\\.(date|)time$)", names(d)))
  utime <- ptime <- FALSE
  if (length(l)) {
    d[, l][d[, l] == ""] <- NA
    ## format timezone
    if (!is.null(d$timezone)) {
      ## add offset in seconds from GMT/UTC
      d$gmtoff <- 0
      ## add time zone identifier
      d$tz <- d$timezone
      if (!is.null(d$utc.to.local.delta)) {
        d$gmtoff <- 60 * d$utc.to.local.delta
        d$tz <- paste("Etc/GMT", c("+", "-")[pmax(1, sign(d$gmtoff) + 1)],
                      formatC(abs(d$gmtoff) / 60^2), sep = "")
        d$tz[is.na(d$gmtoff)] <- ""
      }
      ## indicate whether or not we have sufficient time zone information,
      ## needed to convert local times to POSIXct (Unix time)
      utime <- TRUE
      ## indicate whether or not the date-time variables are local times,
      ## needed to calculate relevent POSIXlt-based variables (e.g. time of day)
      ptime <- !all(d$tz %in% c("GMT", "UTC"))
    }
    ## for each of the character date-time variables...
    ## ... extract the date part
    ## nb: this is does not consider the time zone
    y <- do.call("data.frame", lapply(d[, l, drop = FALSE], char2date))
    names(y) <- gsub("(date|)time", "date", names(y))
    d <- cbind(d, y)
    ## ... using UTC offset, calculate POSIXct date-time and date
    ## nb: these values can be used to put records in chronological order
    if (utime) {
      u <- do.call("data.frame",
                   mapply(char2utime, x = d[, l, drop = FALSE],
                          offset = d[, names(d) == "gmtoff", drop = FALSE],
                          SIMPLIFY = FALSE))
      names(u) <- gsub("(date|)time", "utime", names(u))
      y <- do.call("data.frame", lapply(u, char2date))
      names(y) <- gsub("utime", "udate", names(y))
      d <- cbind(d, u, y)
    }
    ## ... using the time zone, calculate POSIXlt elements
    ## (e.g. day of year (0-366), month (0-11), weekday (0-6), etc.
    if (ptime) {
      p <- do.call("data.frame",
                   mapply(char2calendar, x = d[, l, drop = FALSE],
                          tz = d[, names(d) == "tz", drop = FALSE],
                          SIMPLIFY = FALSE))
      d <- cbind(d, p)
    }
  }
  ## sort by given list of variables
  order.by <- substitute(order.by)
  order.by <- eval(order.by, d)
  if (!is.null(order.by))
    d <- d[do.call("order", order.by), ]
  row.names(d) <- NULL
  print(nrow(d))
  d
}
