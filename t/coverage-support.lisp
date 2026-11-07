(in-package #:ollama-kit/test)

(defun coverage-tree-contains-symbol-p (tree symbol)
  (cond
    ((eq tree symbol) t)
    ((consp tree)
     (or (coverage-tree-contains-symbol-p (car tree) symbol)
         (coverage-tree-contains-symbol-p (cdr tree) symbol)))
    (t nil)))
