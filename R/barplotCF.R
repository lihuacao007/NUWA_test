#' Stacked barplot of cell fractions for samples in different groups.
#'
#' Visualize the estimated cell fractions for multiple groups of samples by a stacked bar chart.
#'
#' @param mat a numeric matrix of cell fractions for bulk samples, with sample identifiers as rownames and cell type names as colnames.
#' @param groupInfo a vector or factor giving the group names for samples in "\code{mat}". The order of "\code{groupInfo}" should be same as the sample order in "\code{mat}" unless it was named by the sample identifiers. You can designate the bar orders of groups by setting "\code{groupInfo}" to factor format following your order of interest. Missing values (NA) will be removed before plotting.
#' @param ctCol a character vector specifying the colors of the different cell types, which should be given in the order of the colnames of "\code{mat}". Default colors will be used if not provided.
#' @export
#'
#' @examples
#' set.seed(2024)
#' promat <- runif(10 * 7,min = 0, max = 1)
#' promat <- matrix(promat, nrow = 10)
#' promat <- promat / rowSums(promat)
#' rownames(promat) <- paste0("sample_", 1:10)
#' colnames(promat) <- paste0("ct_", 1:7)
#' set.seed(2024)
#' groupinfo <- sample(paste0('Group_', letters[1:3]), 10, replace = T)
#' barplotCF(promat, groupInfo = groupinfo)
barplotCF <- function(mat, groupInfo = NULL, ctCol = NULL) {
    if (!is.matrix(mat)) {
        stop("mat should be a matrix")
    }
    if(is.null(rownames(mat))|is.null(colnames(mat))) {
        stop("rownames or colnames of 'mat' should not be null")
    }

    if (length(groupInfo) != nrow(mat)) {
        stop("The length of 'groupInfo' should be the same with the number of samples included in 'mat'")
    }

    if(any(mat < 0 | is.na(mat))){
        warning('Automatically remove samples with NAs or negative numbers!')
        keepind <- rowSums(mat < 0 | is.na(mat))==0
        mat <- mat[keepind,,drop=F]
        if (identical(names(groupInfo), NULL)) {
            groupInfo <- groupInfo[keepind]
        }
    }

    if(any(colSums(mat)==0)) {
        mat <- mat[,colSums(mat)>0,drop=F]
        warning("Remove cell types that equal zero across all samples, including:\n",colnames(mat)[colSums(mat)==0])
    }


    res <- mat / rowSums(mat)


    if (is.null(groupInfo)) {
        groupInfo <- rep("", nrow(res))
    }
    if (!(is.vector(groupInfo) | is.factor(groupInfo))) {
        stop("Parameter 'groupInfo' should be given as a vector or factor")
    }

    samids <- rownames(res)

    if (is.factor(groupInfo)) levs <- levels(groupInfo) else levs <- unique(groupInfo)

    if (!identical(names(groupInfo), NULL)) {
        if (any(duplicated(names(groupInfo)))) {
            stop("The names of groupInfo should be unique")
        }
        ind <- match(names(groupInfo), samids)
        if (any(is.na(ind))) {
            stop("The names of groupInfo should be the same with sample ids in 'mat'")
        }
        groupInfo <- groupInfo[match(samids, names(groupInfo))]
    }
    df <- data.frame(Sample = rownames(res), Group = groupInfo, res,check.names = F)
    df$Sample=factor(df$Sample,levels = rownames(res))
    df <- reshape2::melt(df, id = c("Sample", "Group"), variable.name = "celltype")
    df$Group <- factor(df$Group, levels = levs)
    df$celltype <- factor(df$celltype, levels = colnames(res))
    if (is.null(ctCol)) {
        if (ncol(res)==6) {
            ctCol <- c("#709770", "#71E945", "#CCE744", "#DCA8A1", "#6BDFDC", "#D4D3D5")
        } else {
            ctCol <- rainbow(ncol(res))
        }
    }
    # ct.labs <- c("B", "CD4", "CD8", "NK", "Mono/Macro", "Neutro")
    ct.labs <- colnames(res)
    p <- ggplot2::ggplot(mapping = ggplot2::aes(x = Sample, fill = celltype, y = value), data = df) +
        ggplot2::geom_col(position = "stack") +
        ggplot2::theme(
            axis.text.x = ggplot2::element_text(angle = 270, hjust = 0, vjust = 0.5),
            # strip.text.x = element_text(size = 7),
            strip.background.x = ggplot2::element_blank(),
            panel.background = ggplot2::element_blank(),
            plot.background = ggplot2::element_blank(),
            axis.ticks.x = ggplot2::element_blank()
        ) +
        ggplot2::xlab("") +
        ggplot2::ylab("Fraction") +
        ggplot2::scale_fill_manual(name = NULL, values = ctCol, labels = ct.labs) +
        ggplot2::facet_grid(~Group, scales = "free_x", space = "free_x") +
        ggplot2::scale_y_continuous(expand = c(0, 0), limits = c(0, 1.005))
    print(p)
}


