#!/usr/bin/env Rscript

source("/broad/IDP-Dx_work/nirmalya/research/gene_select_v3/utils.R")
suppressMessages(library(DESeq2))
suppressMessages(library(metap))
suppressMessages(library(docopt))


'Responsive Gene selection script for Mtb

Usage: GeneSelect_Mtb.R --stag <stag> -c <counts> -o <outdir> -s <sus> -t <treated> -u <untreated> -n <timepoints> [--l_cand <l2fc_cand> --base_lim <baseMean % limit> --use_t1] 

options:
  -c <count> --count <count>
  -o <outdir> --outdir <outdir>
  --stag <stag>
  -s <sus> --sus <sus>
  -t <treated> --treated <treated>
  -u <untreated> --untreated <untreated>
  -n <timepoints> --timepoints <timepoints>
  --l_cand <l2fc_cand> [default: 1]
  --base_lim <baseMean % limit> [default: 50]' -> doc
# what are the options? Note that stripped versions of the parameters are added to the returned list

opts <- docopt(doc)
str(opts)  

count_file <- opts$count
outdir <- opts$outdir
sus <- opts$sus
treated <- opts$treated
untreated <- opts$untreated
timepoints <- opts$timepoints
use_t1 <- opts$use_t1

# p_cand is hard coded since we are not using the adjusted p_value cutoff
p_cand <- 0.05
l_cand <- as.numeric(opts$l_cand)

stag <- opts$stag

base_lim_val <- as.numeric(opts$base_lim)

print(paste0("count_file: ", count_file))
print(paste0("l_cand: ", l_cand))
print(paste("use_t1: ", use_t1))

dir.create(outdir, recursive = TRUE)
logfile <- paste0(outdir, "/", stag, "_logfile.txt")
print(logfile)
file.create(logfile)


pval_logfile <- paste0(outdir, "/", stag, "_pval_logfile.txt")
print(pval_logfile)
file.create(pval_logfile)


print(paste0("count_file: " , count_file))
count_tbl <- get_count_tbl(count_file)
print(paste0("count_tbl: ", dim(count_tbl)[2]))

sample_ids <- colnames(count_tbl)
# For TB the sample groups would be extracted in a different way
#sample_groups <- get_sample_groups(sample_ids)
sample_groups <- get_sample_groups_TB(sample_ids, sus, treated, untreated, timepoints)


print("sample_groups")
print(sample_groups)
colData <- get_colData(sample_groups)
str(colData)
lsamples <- rownames(colData)
countData <- count_tbl[, lsamples] 
print("countData")
str(countData)
tp_parts <- sample_groups$exp_conds$tp_parts

treated_start <- NA
if (use_t1) {
    treated_start <- 1
} else {
    treated_start <- 2
}

print("Running the DESeq2 tests.")
res_lst <- list()
basemean_lst <- list()
gene_count <-  dim(countData)[1]
tp_len <- length(tp_parts)
for (j in treated_start:tp_len) {
    for (k in 1:tp_len) {
        treated_term <- paste0('sus_treated_time', j)
        untreated_term <- paste0('sus_untreated_time', k) 
        print(treated_term)
        print(untreated_term)
        print("---------")
        lres <- deseq_condwise_part(countData, sample_groups, treated_term, 
            untreated_term, lfcth = l_cand, padjth = p_cand, 
            altH = "greaterAbs", use_beta_prior = FALSE, base_lim = base_lim_val) 
        name_term = paste0(treated_term, "__", untreated_term)
        res_lst[[name_term]] <- data.frame(lres$lres)
        basemean_lst[[name_term]] <- lres$baseMean_lim_val
    }
}


print("Starting gene selection procedure..")
gene_lst <- rownames(countData)
pval_lim_raw <- 0.05
gene_res <- select_genes(gene_lst, tp_len, res_lst, basemean_lst, pval_lim_raw, treated_start, use_res = FALSE)
# Now process per gene.
gene_cond_lst <- gene_res$"gene_cond_lst"
gene_cond_raw_lst <- gene_res$"gene_cond_raw_lst"
lmethod <- "fisher"
sum_pvals_lst <- lapply(gene_cond_lst, get_meta_pval, lmethod)
# adjusted p-value cutoff limit

sum_pvals <- unlist(sum_pvals_lst)
sum_pvals_s <- sort(sum_pvals)

print_log("Starting Fisher's method")
sorted_genes <- names(sum_pvals_s)
final_df <- data.frame(matrix(ncol = 2, nrow = 0))
selected_genes <- c()
lcount <- 0
for (lgene_cond in sorted_genes) {
    parts <- strsplit(lgene_cond, "__")
    lgene <- parts[[1]][1]
    lcond <- parts[[1]][2]
    if (!(lgene %in% selected_genes)) {
        selected_genes <- c(selected_genes, lgene)
        final_df[lgene, 1] = sum_pvals_s[lgene_cond]
        final_df[lgene, 2] = lcond
        lcount <- lcount + 1
    }
    
}

sign_df <- data.frame(matrix(ncol = 1, nrow = 0))

for (lgene_cond in sorted_genes) {
    # Get the treated cond
    parts <- strsplit(lgene_cond, "__")
    lgene <- parts[[1]][1]
    lcond <- parts[[1]][2]

    # Replace the treated trem in the lcond with untreated

    lcond_un <- sub('treated', 'untreated', lcond)
    combined_cond <- paste0(lcond, "__", lcond_un)

    lcomp <- res_lst[[combined_cond]]
    l2fc_val <- lcomp[lgene, "log2FoldChange"]

    l2fc_sign <- "."

    if (is.na(l2fc_val)) {
        l2fc_sign <- "NA"
    } else if (l2fc_val >=0) {
        l2fc_sign <- "+"
    } else if(l2fc_val){
        l2fc_sign <- "-"
    }

    locus_tag <- sub("^CDS:(\\S+?):.*$", "\\1", lgene)
    sign_df[locus_tag, 1] <- l2fc_sign

}

colnames(final_df) <- c("Fishers_pvalue", "treated_cond")
genelst_file <- paste0(outdir, "/", stag, "_genelist.txt")
write.table(final_df, genelst_file, sep = "\t", quote = FALSE)

reg_tab_file <- paste0(outdir, "/", stag, "_genes_homology.txt")
write.table(sign_df, reg_tab_file, sep = "\t", quote = FALSE, col.names = FALSE)
sorted_final_genes <- sort(selected_genes)

print(selected_genes)

        

