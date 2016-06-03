;;; counsel-css.el --- stylesheet-selector-aware swiper
;;
;; Copyright (C) 2016 Henrik Lissner
;;
;; Author: Henrik Lissner <http://github/hlissner>
;; Maintainer: Henrik Lissner <henrik@lissner.net>
;; Created: June 3, 2016
;; Modified: June 3, 2016
;; Version: 1.0.0
;; Keywords: counsel, swiper, css, less, scss
;; Homepage: https://github.com/hlissner/emacs-counsel-css
;; Package-Requires: ((counsel "0.7.0") (cl-lib "0.5))
;;
;; This file is not part of GNU Emacs.
;;
;;; License: GPLv3
;;
;;; Commentary:
;;
;; This plugin tries to fill that multi-cursor shaped gap in your heart, by integrating
;; iedit-mode into evil-mode.
;;
;;; Code:

(eval-when-compile
  (require 'cl-lib))

(defgroup counsel-css nil
  "css/less/scss selector-aware swiper."
  :prefix "counsel-css-"
  :group 'ivy)

(defface counsel-css-selector-depth-face-1
  '((((class color) (background dark)) (:foreground "#ffff00"))
    (((class color) (background light)) (:foreground "#0000ff"))
    (t (:foreground "#ffff00")))
  "Selector depth 1"
  :group 'counsel-css)
(defface counsel-css-selector-depth-face-2
  '((((class color) (background dark)) (:foreground "#ffdd00"))
    (((class color) (background light)) (:foreground "#3300ff"))
    (t (:foreground "#ffdd00")))
  "Selector depth 2"
  :group 'counsel-css)
(defface counsel-css-selector-depth-face-3
  '((((class color) (background dark)) (:foreground "#ffbb00"))
    (((class color) (background light)) (:foreground "#6600ff"))
    (t (:foreground "#ffbb00")))
  "Selector depth 3"
  :group 'counsel-css)
(defface counsel-css-selector-depth-face-4
  '((((class color) (background dark)) (:foreground "#ff9900"))
    (((class color) (background light)) (:foreground "#9900ff"))
    (t (:foreground "#ff9900")))
  "Selector depth 4"
  :group 'counsel-css)
(defface counsel-css-selector-depth-face-5
  '((((class color) (background dark)) (:foreground "#ff7700"))
    (((class color) (background light)) (:foreground "#cc00ff"))
    (t (:foreground "#ff7700")))
  "Selector depth 5"
  :group 'counsel-css)
(defface counsel-css-selector-depth-face-6
  '((((class color) (background dark)) (:foreground "#ff5500"))
    (((class color) (background light)) (:foreground "#ff00ff"))
    (t (:foreground "#ff5500")))
  "Selector depth 6"
  :group 'counsel-css)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(cl-defun counsel-css--open-brace-forward (&optional $bound)
  "Move to next open brace, skip commented brace"
  (interactive)
  (let ($ret)
    (setq $ret (re-search-forward "[^#]{" $bound t))
    (unless $ret (return-from counsel-css--open-brace-forward nil))
    (backward-char)
    (if (counsel-css--comment-p (point))
        (counsel-css--open-brace-forward $bound)
      $ret)))

(defun counsel-css--substr-last-string ($text $key)
  "Return the tail of $text without $key strings"
  (while (string-match $key $text)
    (setq $text (substring $text (1+ (string-match $key $text)))))
  $text)

(cl-defun counsel-css--fetch-previous-line (&optional $prev $noexcursion)
  "Return previous nth ($prev) line strings.
If $noexcursion is not-nil cursor doesn't move."
  ;; In compressed Css without this return, it takes long time
  (if (eq 1 (line-number-at-pos))
      (return-from counsel-css--fetch-previous-line ""))
  (or $prev (setq $prev 1))
  (if $noexcursion (setq $noexcursion (point)))
  (move-beginning-of-line (- 1 $prev))
  (let (($po (point)) $res)
    (move-end-of-line 1)
    (setq $res (buffer-substring-no-properties $po (point)))
    (if $noexcursion (goto-char $noexcursion))
    $res))

(defun counsel-css--comment-p (&optional $pos)
  (or $pos (setq $pos (point)))
  (nth 4 (parse-partial-sexp (point-min) $pos)))

(cl-defun counsel-css--extract-selector ()
  "Return selector infomation at the point"
  (let (($multi "") $s $po1 $po2 $po3 $str $commentp)
    ;; Collect multiple selector across previous lines
    ;; (i.e. "div, \n p, \n span {...}")
    (save-excursion
      (while (string-match ",[\s\t]*$"
                           (setq $s (counsel-css--fetch-previous-line)))
        ;; Skip commented selector (i.e. " // .blue,")
        (save-excursion
          (move-beginning-of-line 1)
          (setq $po3 (point))
          (setq $commentp (counsel-css--comment-p (search-forward ","))))
        (unless $commentp
          (setq $multi (format "%s %s" (string-trim $s) $multi)))))
    ;; Extract selector include one-line-nesting (i.e. "div { p {...} }")
    (save-excursion
      (skip-chars-backward "^{};\n")
      (setq $po1 (point))
      ;; (setq $beg2 $po1)
      (skip-chars-forward "^{")
      (setq $po2 (point))
      (setq $str (buffer-substring-no-properties $po1 $po2))
      ;; i.e. "div { .box { p"  ->  " p"
      (setq $str (counsel-css--substr-last-string $str "{\\|}"))
      (setq $str (string-trim $str))
      ;; Return (selector-name . (selector-beginning-point . selector-end-point))
      (if (equal $multi "")
          (cons (format "%s" $str) (cons $po1 $po2))
        (cons (format "%s %s" (string-trim $multi) $str)
              (cons $po3 $po2))))))

(cl-defun counsel-css--selector-next (&optional $bound)
  "Return and goto next selector."
  (unless (counsel-css--open-brace-forward $bound)
    (return-from counsel-css--selector-next nil))
  (counsel-css--extract-selector))

(defun counsel-css--selector-to-hash ()
  "Collect all selectors and make hash table"
  (let ($selector $paren-beg $paren-end $hash $dep $max $sl
                  $selector-name $selector-beg $selector-end
                  $selector-line)
    (setq $hash (make-hash-table :test 'equal))
    (save-excursion
      (goto-char (point-min))
      (while (setq $selector (counsel-css--selector-next))
        (setq $paren-beg (point))
        (setq $paren-end (scan-sexps $paren-beg 1))
        (setq $max (cons $paren-end $max))
        (setq $max (mapcar (lambda ($p) (if (< $p $paren-beg) nil $p)) $max))
        (setq $max (delq nil $max))
        (setq $dep (length $max))
        (setq $selector-name (car $selector))
        (setq
         $selector-name
         (cl-case $dep
           (1 (propertize $selector-name 'face 'counsel-css-selector-depth-face-1))
           (2 (propertize $selector-name 'face 'counsel-css-selector-depth-face-2))
           (3 (propertize $selector-name 'face 'counsel-css-selector-depth-face-3))
           (4 (propertize $selector-name 'face 'counsel-css-selector-depth-face-4))
           (5 (propertize $selector-name 'face 'counsel-css-selector-depth-face-5))
           (6 (propertize $selector-name 'face 'counsel-css-selector-depth-face-6))))
        (setq $selector-beg (cadr $selector))
        (setq $selector-end (cddr $selector))
        (setq $selector-line (line-number-at-pos $selector-beg))
        (if (<= $dep (length $sl))
            (loop repeat (- (1+ (length $sl)) $dep) do (pop $sl)))
        (setq $sl (cons $selector-name $sl))
        (puthash (format "%s: %s"
                         (propertize (number-to-string
                                      $selector-line)
                                     'face 'font-lock-function-name-face)
                         (mapconcat 'identity (reverse $sl) " "))
                 (list $paren-beg $paren-end $dep $selector-beg $selector-end $selector-line)
                 $hash)))
    $hash))

(defun counsel-css--imenu-create-index-function ()
  (let (($hash (counsel-css--selector-to-hash)))
    (loop for $k being hash-key in $hash using (hash-values $v)
          collect (cons $k $v))))

;;;###autoload
(defun counsel-css-imenu-setup ()
  (when (memq major-mode '(css-mode scss-mode less-css-mode))
    (setq imenu-create-index-function 'counsel-css--imenu-create-index-function)))

;;;###autoload
(defun counsel-css ()
  (interactive)
  (require 'counsel)
  (ivy-read "Selectors: " (let (($hash (counsel-css--selector-to-hash)))
                            (loop for $k being hash-key in $hash using (hash-values $v)
                                  collect (cons $k $v)))
            :require-match t
            :caller 'counsel-css))

(provide 'counsel-css)
;;; counsel-css.el ends here
