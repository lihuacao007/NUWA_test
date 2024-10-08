
completeness.ccb2 <- function(m, threshold = 50, nsams = 10, use.sams = F) {
    # debug.message(paste("Before completeness:", nrow(df),"rows,", ncol(df), "columns"))
    if (use.sams) {
        completeness <- sapply(1:nrow(m), function(i) sum(!is.na(m[i, ])))
        y <- m[completeness >= nsams, ]
    } else {
        completeness <- sapply(1:nrow(m), function(i) {
            sum(!is.na(m[i, ])) / ncol(m) * 100
        })
        y <- m[completeness >= threshold, ]
    }
    # debug.message(paste("After completenessAndimpute:", nrow(y),"rows,", ncol(y), "columns"))
    return(y)
}



cor_col <- function(x, method = "pearson", subset = NULL, ncores = 4) {
    if (is.null(colnames(x))) stop("colnames of x should not be null")
    is.window <- (get_os() == "windows")
    if (is.window) {
        ncores <- 1
        cl <- parallel::makePSOCKcluster(ncores)
    } else {
        ncores <- min(ncores, parallel::detectCores() - 1)
        cl <- parallel::makeForkCluster(ncores)
        parallel::clusterSetRNGStream(cl)
    }

    if (is.null(subset)) {
        subset <- colnames(x)
    } else {
        subset <- intersect(subset, colnames(x))
    }
    all0 <- union(subset, colnames(x))
    x <- x[, all0, drop = F]
    cormat <- parallel::parSapply(
        cl, seq_along(subset),
        function(i) {
            x0 <- x[, i]
            sapply(seq_along(all0), function(j) {
                if (j <= i) {
                    return(NA)
                }
                y0 <- x[, j]
                ct0 <- tryCatch(
                    {
                        cor.test(x0, y0, method = method)
                    },
                    error = function(e) {
                        return(NULL)
                    }
                )
                if (is.null(ct0)) {
                    return(NA)
                }
                if (!is.na(ct0$p.value) & ct0$p.value <= 0.05) {
                    return(ct0$estimate)
                } else {
                    return(NA)
                }
            })
        }
    )
    parallel::stopCluster(cl)
    rownames(cormat) <- all0
    colnames(cormat) <- subset
    cormat
}

rm.outlier <- function(x, usecap = T) {
    qnt <- quantile(x, probs = c(.25, .75), na.rm = T)
    H <- 1.5 * IQR(x, na.rm = T)
    if (usecap) {
        caps <- quantile(x, probs = c(.05, .95), na.rm = T)
        x[x < (qnt[1] - H)] <- caps[1]
        x[x > (qnt[2] + H)] <- caps[2]
    } else {
        x[x < (qnt[1] - H)] <- NA
        x[x > (qnt[2] + H)] <- NA
    }
    return(x)
}

get_os <- function() {
    sysinf <- Sys.info()
    if (!is.null(sysinf)) {
        os <- sysinf["sysname"]
        if (os == "Darwin") {
            os <- "osx"
        }
    } else { ## mystery machine
        os <- .Platform$OS.type
        if (grepl("^darwin", R.version$os)) {
            os <- "osx"
        }
        if (grepl("linux-gnu", R.version$os)) {
            os <- "linux"
        }
    }
    tolower(os)
}

random.mat <- function(m, n) {
    y <- matrix(rnorm(m * n), m, n)
    rownames(y) <- paste0("row", seq(m))
    colnames(y) <- paste0("col", seq(n))
    y
}

merge.list <- function(dfls, ...) {
    df0 <- NULL
    for (df in dfls) {
        if (identical(df0, NULL)) {
            df0 <- df
        } else {
            df0 <- merge(df0, df, ...)
        }
    }
    return(df0)
}

global.scale <- function(x) {
    a <- min(x, na.rm = T)
    b <- max(x, na.rm = T)
    y <- (x - a) / (b - a)
    revfun <- function(y) {
        x <- (y * (b - a)) + a
        return(x)
    }
    res <- list(
        y = y,
        reverseFun = revfun
    )
    return(res)
}

global.scale.zscore <- function(x) {
    a <- mean(x, na.rm = T)
    b <- sd(x, na.rm = T)
    y <- (x - a) / b
    revfun <- function(y) {
        x <- (y * b) + a
        return(x)
    }
    res <- list(
        y = y,
        reverseFun = revfun
    )
    return(res)
}


# input: a vector of gene symbols
# output: a data.frame contains original symbols, standardized symbols and HGNC status
standardized_symbol <- function(symbols, hgnc_file=NULL) {
    url <- "https://www.genenames.org/cgi-bin/download/custom?col=gd_app_sym&col=gd_status&col=gd_prev_sym&col=gd_aliases&col=gd_pub_eg_id&status=Approved&status=Entry%20Withdrawn&hgnc_dbtag=on&order_by=gd_app_sym_sort&format=text&submit=submit"

    if(is.null(hgnc_file)){
        hgnc_file = paste0("hgnc_symbols_",format(Sys.time(), "%Y-%m"),".txt")
    }
    if(!file.exists(hgnc_file)){
        hgnc <- read.delim(url, stringsAsFactors = F, fill = T)
        write.table(x = hgnc, file = hgnc_file, quote = F, sep = "\t", row.names = F, col.names = T)
    }
    hgnc <- read.delim(hgnc_file, stringsAsFactors = F, fill = T, header = T, sep = "\t")

    hgnc <- subset(hgnc, Status=="Approved")

    approved_count <- 0
    previous_count <- 0
    alias_count <- 0
    not_found <- 0

    Standardized_Symbol <- vector()
    HGNC_status <- vector()

    for (x in symbols) {
        if (x %in% hgnc$Approved.symbol) {
            approved_count <- approved_count + 1
            Standardized_Symbol <- c(Standardized_Symbol, x)
            HGNC_status <- c(HGNC_status, "Approved symbol")

        } else {

            previous <- sapply(hgnc$Previous.symbols,function(y) {
                tmp <- unlist(strsplit(y,",\\s+"))
                return(x %in% tmp)
            })

            alias <- sapply(hgnc$Alias.symbols,function(y) {
                tmp <- unlist(strsplit(y,",\\s+"))
                return(x %in% tmp)
            })

            if (any(previous)) {
                previous_count <- previous_count + 1
                previous.df <- subset(hgnc, previous)
                hgnc_symbols <- paste0(unique(previous.df$Approved.symbol), collapse = ",")
                Standardized_Symbol <- c(Standardized_Symbol, hgnc_symbols)
                HGNC_status <- c(HGNC_status, "Previous symbol")

            } else if(any(alias)) {
                alias_count <- alias_count + 1
                alias.df <- subset(hgnc, alias)
                hgnc_symbols <- paste0(unique(alias.df$Approved.symbol), collapse = ";")
                Standardized_Symbol <- c(Standardized_Symbol, hgnc_symbols)
                HGNC_status <- c(HGNC_status, "Alias symbols")

            } else {
                not_found <- not_found + 1
                Standardized_Symbol <- c(Standardized_Symbol, x)
                HGNC_status <- c(HGNC_status, "not found")
            }
        }
    }

    message(paste0("No. of input symbols: ", length(symbols)))
    message(paste0("No. of matched by approved symbols: ", approved_count))
    message(paste0("No. of matched by previous symbol: ", previous_count))
    message(paste0("No. of matched by alias symbol: ", alias_count))
    message(paste0("No. of not found: ", not_found))

    annotated_symbol <- data.frame(original_symbol = symbols,
                                   Standardized_Symbol = Standardized_Symbol,
                                   HGNC_status = HGNC_status)

    return(annotated_symbol)
}

geneidcorrect <- function(mat, hgnc_file = hgnc_f) {
    ids0 <- rownames(mat)
    ids <- standardized_symbol(ids0, hgnc_file = hgnc_file)$Standardized_Symbol
    df <- data.frame(id = ids, mat)
    mat1 <- unisymbol(df, split = c(";", ","))
    return(mat1)
}



recallsum <- function(df, thre = 0.8) {
    levs <- as.character(unique(df$level))
    res <- sapply(levs, function(lev) {
        cat0(lev, "-------------")
        df0 <- df[df$level == lev, ]
        total <- nrow(df0)
        high <- nrow(df0[df0$recall >= thre, ])
        cat0("# Total:", total)
        cat0("# High Recall:", high)
        cat0("Percentage:", round(100 * high / total, 2), "%")
        y <- c(
            num_total = total,
            num_highrecall = high
        )
    })
    res <- data.frame(level = levs, t(res))
    res$percentage = round(res$num_highrecall / res$num_total, 4)
    res
}
cat0 <- function(...) cat(..., "\n")



get_os <- function(){
    sysinf <- Sys.info()
    if (!is.null(sysinf)){
        os <- sysinf['sysname']
        if (os == 'Darwin')
            os <- "osx"
    } else { ## mystery machine
        os <- .Platform$OS.type
        if (grepl("^darwin", R.version$os))
            os <- "osx"
        if (grepl("linux-gnu", R.version$os))
            os <- "linux"
    }
    tolower(os)
}

global.scale <- function(x) {
    a <- min(x, na.rm = T)
    b <- max(x, na.rm = T)
    y <- (x - a) / (b - a)
    revfun <- function(y) {
        x <- (y * (b - a)) + a
        return(x)
    }
    res <- list(
        y = y,
        reverseFun = revfun
    )
    return(res)
}


global.scale.zscore <- function(x) {
    a <- mean(x, na.rm = T)
    b <- sd(x, na.rm = T)
    y <- (x - a) / b
    revfun <- function(y) {
        x <- (y * b) + a
        return(x)
    }
    res <- list(
        y = y,
        reverseFun = revfun
    )
    return(res)
}


CTdeconv.avg <- function(mix, cibersortPath, BCIC_min_marker_num = 6,
                         LM6_min_marker_num = 6, LM22_min_marker_num = 6,
                         RNAseq=F, protein=F, filename=NULL) {
    listmode <- F
    if (is.list(mix) & !is.data.frame(mix)) {
        mixls <- lapply(mix, function(x) {x[x < 0] <- 0; x})
        listmode <- T # Don't use this mode.
        if (length(mixls) == 0) stop("Error: listmode error")
    } else {
        if (!isSingleString(mix) && !is.matrix(mix)) {
            stop("'mix' needs to be given as a matrix or string path")
        }
        if (isSingleString(mix)) {
            mix <- read.delim(mix, row.names = 1, check.names = F)
            mix <- data.matrix(mix)
        }
        mix[mix < 0] <- 0
    }
    if (!is.null(filename) && length(filename) != 2) {
        stop("'filename' needs to be given as
             a string vector with 2 items or NULL")
    }
    combs <- c("epic_bcic", "cibersort_lm6", "cibersort_lm22")
    combid <- seq_along(combs)
    names(combid) <- names(combs) <- combs
    if (protein) {
        RNAseq <- F
        ## 118 genes
        siggs <- union(EPIC::BRef$sigGenes, EPIC::TRef$sigGenes)
    } else {
        ## 65 genes
        siggs <- EPIC::BRef$sigGenes
    }
    ref <- EPIC::BRef
    ref$sigGenes <- siggs

    if (listmode) {
        use <- sapply(combs, function(x) x %in% names(mixls))
    } else {
        siggsls <- list(siggs, rownames(lm6), rownames(lm22))
        names(siggsls) <- combs
        gs_mix <- rownames(mix)
        mar_num <- c(BCIC_min_marker_num,
                     LM6_min_marker_num, LM22_min_marker_num)
        use <- sapply(combid, function(i) {
            gs <- intersect(gs_mix, siggsls[[i]])
            return(length(gs) >= mar_num[i])
        })
    }
    if (listmode) mix <- mixls[["epic_bcic"]]
    epicRes0 <- tryCatch({
        options(warn = -1)
        epicgs <- intersect(rownames(EPIC::BRef$refProfiles), rownames(mix))
        if (length(epicgs) < 2e3) scale_expr <- F else scale_expr <- T
        a <- EPIC::EPIC(mix, ref, scaleExprs = scale_expr)
        options(warn = 0)
        a
    }, error = function(e) NULL)
    excluEpic <- identical(epicRes0, NULL)
    epicRes <- if (excluEpic) NULL else epicRes0[["mRNAProportions"]]
    qn <- !RNAseq
    if (listmode) mix <- mixls[["cibersort_lm6"]]
    cib_lm6_res <- tryCatch(CIBERSORT(lm6, mix, QN = qn),
                            error = function(e) NULL)
    if (listmode) mix <- mixls[["cibersort_lm22"]]
    cib_lm22_res <- tryCatch(CIBERSORT(lm22, mix, QN = qn),
                             error = function(e) NULL)
    resls <- list(epicRes, cib_lm6_res, cib_lm22_res)
    isNull <- sapply(resls, function(x) identical(x, NULL))
    use <- use & (!isNull)
    names(resls) <- combs
    if (sum(use) == 0) {
        cat("The number of genes included in both mixture and signatures:\n")
        marknum <- sapply(siggsls, function(x) length(intersect(gs_mix, x)))
        print(marknum)
        stop("There is no combination qualified. You can loose the
             restrictions on marker gene number based on the above infomation.")
    }
    resls_good <- lapply(resls[!isNull], function(x) x)
    celllist <- list(
        B = c("B cells naive", "B cells memory", "Bcells", "B cells"),
        CD4 = c("CD4_Tcells", "CD4 T cell", "CD4 T cells", "CD4.T.cells",
                "T cells CD4 naive", "T cells CD4 memory resting",
                "T cells CD4 memory activated",
                "T cells regulatory (Tregs)", "T cells follicular helper"),
        CD8 = c("T cells CD8", "CD8_Tcells", "CD8 T cells",
                "CD8 T cell", "CD8.T.cells"),
        NK = c("NKcells", "NK cells", "NK cell",
               "NK.cells", "NK cells activated"),
        Mono_Macro = c("Monocytes", "Macrophages M0",
                       "Macrophages M1", "Macrophages M2"),
        Neutro = c("Neutrophil", "Neutrophils")
    )
    resls_merged <- lapply(resls_good, mergecell, celllist = celllist)
    resls_use <- resls_good[use[names(resls_good)]]
    if (protein) {
        resls6c <- lapply(resls_use, mergecell, celllist = celllist)
        res_array6c <- abind::abind(resls6c, along = 3)
        res6c <- apply(res_array6c, c(1, 2), mean, na.rm = T)
        res <- res6c
    } else {
        celllist1 <- celllist["CD4" != names(celllist)]
        resls5c <- lapply(resls_use, mergecell, celllist = celllist1)
        res_array5c <- abind::abind(resls5c, along = 3)
        res5c <- apply(res_array5c, c(1, 2), mean, na.rm = T)
        res <- resls_merged[["cibersort_lm22"]]
        res[, -2] <- (1 - res[, 2]) * res5c
    }

    mRNAProp <- res
    if (!protein) {
        renormalize_vector <- c(
            "B" = 0.4016,
            "CD4" = 0.3952,
            "CD8" = 0.3952,
            "NK" = 0.4396,
            "Mono_Macro" = 1.4196,
            "Neutro" = 0.1300)
        res <- t(t(res) / renormalize_vector)
        res <- res / rowSums(res)
        cellProp <- res
    } else cellProp <- NULL
    fres <- list(mRNAProp, cellProp, resls_merged, resls, use)
    names(fres) <- c("prop", "cellProp", "mergedProp", "rawRes", "usedComb")
    if (!is.null(filename)) {
        for (i in 1:2) {
            res <- fres[[i]]
            fname <- filename[i]
            if (!is.na(fname)) {
                res1 <- data.frame(SampleId = rownames(res),
                                   res, check.names = F)
                write.table(res1, fname, row.names = F, sep = "\t", quote = F)
            }
        }
    }
    return(fres)
    }

write.mat <- function(mat, file) {
    write.table(df, file = file, row.names = F, sep = "\t", quote = F)
    invisible()
}

#single string detector
isSingleString <- function(input) {
    is.character(input) & length(input) == 1
}

## modify CIBERSORT.R to make it compatible with single sample input.
ciber_modify <- function(path, protein = F) {
    con <- file(path)
    f <- readLines(con, warn = F)
    close(con)
    new_path <- paste0(tempdir(), "\\CIBERSORTtemp.R")
    pat <- "(\\[.+,) *(\\])"
    f <- gsub(pat, "\\1,drop=F\\2", f)
    if (protein) {
        f[grepl("< 50", f)] <- paste0("#", f[grepl("< 50", f)])
    }
    write.table(f, file = new_path, sep = "\n",
                quote = F, row.names = F, col.names = F)
    new_path
}


mergecell <- function(x, celllist) {
    y <- sapply(celllist, function(i) {
        x1 <- x[, colnames(x) %in% i, drop = F]
        x1 <- rowSums(x1)
    })
    if (!is.matrix(y)) y <- matrix(y, nrow = 1)
    colnames(y) <- names(celllist)
    y <- y / rowSums(y)
}

# remove genes with NAs in all samples of one batch.
rmbatchrow <- function (exp, batch) {
    identical.x <- function(x) {
        x <- x[!is.na(x)]
        return(length(unique(x)) <= 1)
    }
    iden_mat <- sapply(
        unique(batch),
        function(b) {
            apply(exp[, batch == b], 1, identical.x)
        }
    )
    rmline <- apply(iden_mat, 1, any)
    exp <- exp[!rmline, ]
    return(exp)
}





