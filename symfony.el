;;; symfony.el -- minor mode for editting PHP symfony flamework code.

;; Copyright (c) 2009 by KAYAC Inc.

;; Author: IMAKADO <ken.imakado -at-  gmail.com>
;; blog: http://d.hatena.ne.jp/IMAKADO (japanese)
;; Prefix: sf:

;; This file is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.

;; This file is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.


;;; Commentary:

;; tested only on emamcs22

;;; Installation:

;; install these libraries:
;; `anything.el' http://www.emacswiki.org/emacs/anything.el
;; `anything-match-plugin.el'  http://www.emacswiki.org/emacs/anything-match-plugin.el
;; `anything-project.el' http://github.com/imakado/emacs-symfony/tree/master
;; `symfony.el' http://github.com/imakado/emacs-symfony/tree/master

;; add these lines to your .emacs file:
;; (require 'symfony)


;;; TODO:
;; - Commands to run symfony command.
;; - Code Completion

(require 'cl)
(require 'rx)
(require 'php-mode)
(require 'anything)
(require 'anything-match-plugin)
(require 'anything-project)


;; i'm not sure, anyone can change this? - IMAKADO
(defconst sf:MODULES-DIR-NAME "modules")
(defconst sf:TEMPLATES-DIR-NAME "templates")
(defconst sf:APP-MODULE-ACTION-DIR-NAME "actions")
(defconst sf:ACTIONS-CLASS-PHP "actions.class.php")
(defconst sf:ACTIONS-FILE-RULE "Action.class.php")

(defvar sf:mode-directory-rules
  `(
    (action ,(rx-to-string `(and  "apps/" (+ not-newline) "/" ,sf:APP-MODULE-ACTION-DIR-NAME)))
    (template ,(rx-to-string `(and  "apps/" (+ not-newline) "/" ,sf:TEMPLATES-DIR-NAME)))
    ))

(defvar sf:primary-switch-fn 'sf-cmd:all-project-files
  "minor mode overide this")
(make-variable-buffer-local 'sf:primary-switch-fn)

(defvar sf:after-anything-project-action-hook nil
  "list of functions called after anything project(symfony-mode's `find-file').
Note,this variable MUST BE let bounded in command.
e.x,
 (let ((sf:after-anything-project-action-hook
        (list
         (lambda () (re-search-forward \"function_name\" nil t)))))
   (sf:anything-project candidates))")

(defcustom sf:anything-project-exclude-regexps nil
  "list of regexp or just regexp")

(defvar sf:previous-log-file nil)

(defun sf:project-absolute-path (file-name)
  (assert (stringp file-name))
  (cond
   ((file-name-absolute-p file-name)
    file-name)
   (t
    (let ((root-dir (sf:get-project-root)))
      (if root-dir
        (sf:catdir root-dir file-name)
        "")))))

(defun sf:buffer-type ()
  (loop for (type re-or-fn) in sf:mode-directory-rules
        when (if (stringp re-or-fn)
                 (string-match (sf:project-absolute-path re-or-fn) (sf:current-directory))
               (funcall re-or-fn))
        do (return type)))

(defun sf:current-directory ()
  (file-name-directory
   (expand-file-name
    (or (buffer-file-name)
        default-directory))))

(defun sf:this-file-name ()
  (unless buffer-file-name
    (error "this buffer maybe not saved!!"))
  (file-name-nondirectory buffer-file-truename))

;;; LIB
(defconst sf:find-upper-directory-limit 10)
(defvar sf:root-detector-fn
  (lambda (current-directory)
    (assert (file-directory-p current-directory))
    (let ((files (directory-files current-directory)))
      (let ((symfony-files '("apps" "config")))
        (every
         (lambda (file)
           (find file files :test 'string=))
         symfony-files)))))

(defun sf:get-project-root ()
  (let ((cur-dir (sf:current-directory)))
    (sf:find-upper-directiory sf:root-detector-fn)))

(defun sf:find-upper-directiory (cond-fn)
  (assert (functionp cond-fn))
  (let ((cur-dir (sf:current-directory)))
    (loop with count = 0
        until (funcall cond-fn cur-dir)
        if (= count sf:find-upper-directory-limit)
        do (return nil)
        else
        do (progn (incf count)
                  (setq cur-dir (expand-file-name (concat cur-dir "../"))))
        finally return cur-dir)))

(defun sf:take-function-name ()
  (ignore-errors
    (save-excursion
      (forward-line 1)
      (let ((fname-re (rx bol
                          (* space)
                          "public function"
                          (+ space)
                          (group
                           (+
                            (or (syntax word) (syntax symbol))))
                          "("
                          )))
        (when (re-search-backward fname-re nil t)
          (match-string-no-properties 1))))))

(defun sf:take-off-execute (s)
  (when (stringp s)
    (replace-regexp-in-string (rx bol "execute") "" s)))

(defun sf:take-off-action (s)
  (when (stringp s)
    (let ((case-fold-search nil))
      (replace-regexp-in-string (rx "Action" eol) "" s))))

(defun sf:take-off-tail-capital (s)
  (let ((case-fold-search nil))
  (when (stringp s)
    (when (string-match (rx bol (group (+ print)) (regexp "\\(?:[A-Z][a-z]+\\)") eol) s)
      (match-string 1 s)))))


(defun sf:catdir (s1 s2)
  (let ((s1 (replace-regexp-in-string (rx "/" eol) "" s1))
        (s2 (replace-regexp-in-string (rx bol "/") "" s2)))
    (concat s1 "/" s2)))

(defun* sf:project-files (&optional clear-cache (include-regexps '(".*")) (exclude-regexps sf:anything-project-exclude-regexps))
  (setq clear-cache (or clear-cache current-prefix-arg))
  (let ((root-dir (sf:get-project-root)))
    (unless root-dir
      (error "this buffer is not symfony project file"))
    (let ((ap:projects nil))
      (ap:add-project
       :name 'symfony
       :look-for sf:root-detector-fn
       :grep-extensions '("\\.php"))
      (when clear-cache
        (setq ap:--cache
              (delete-if (lambda (ls) (equal root-dir ls))
                         ap:--cache
                         :key 'car)))
      (lexical-let ((root-dir root-dir))
        (setq ap:root-directory root-dir)
        (ap:cache-get-or-set
         root-dir
         (lambda ()
           (message "getting project files...")
           (let ((include-regexp include-regexps)
                 (exclude-regexp exclude-regexps))
             (let* ((files (ap:directory-files-recursively
                            include-regexp
                            root-dir
                            'identity
                            exclude-regexp)))
               files))))))))

(defun sf:abs->relative (los)
  (assert (listp los))
  (mapcar 'file-relative-name los))

(defun sf:get-module-dir-or-root ()
  (let ((cur-dir (sf:current-directory)))
    (cond
     ((string-match (rx (group bol (* not-newline) "apps" (+ not-newline) "modules" (? "/")))
                    cur-dir)
      (match-string 1 cur-dir))
     (t
      (sf:get-project-root)))))

(defun sf:get-templates-directory ()
  (let ((templates-finder
         (lambda (cur-dir)
           (let ((template-dir (sf:catdir cur-dir (concat "/" sf:TEMPLATES-DIR-NAME "/"))))
             (file-directory-p template-dir)))))
    (let ((ret (sf:find-upper-directiory templates-finder)))
      (when ret
        (list (sf:catdir ret sf:TEMPLATES-DIR-NAME))))))



(defun sf:get-templates-file-by-action-name (action-name)
  "return list of templates or nil
Note, dont return just STRING even if find one template file."
  (let ((files (sf:get-templates-directory)))
    files))

(defcustom sf:quickly-find-file-when-candidates-length-is-1 t
  "if this variable is set to non-nil and candidates is just one,
find file quickly (dont use anything interface)")

(defun sf:anything-project (--candidates)
  (cond
   ((and sf:quickly-find-file-when-candidates-length-is-1
         (= (length --candidates) 1))
    (sf:anything-project-find-file (first --candidates)))
   (t
    (let ((source
           `((name . ,(format "Project files. root: %s" (or (sf:get-project-root) "")))
             (init . (lambda ()
                       (with-current-buffer (anything-candidate-buffer 'local)
                         (insert (mapconcat 'identity --candidates "\n")))))
             (candidates-in-buffer)
             (action . (("Find file" .
                         sf:anything-project-find-file))))))
      (anything (list source))))))

(defun sf:anything-project-find-file (c)
  (find-file c)
  (ignore-errors (run-hooks 'sf:after-anything-project-action-hook)))


(defsubst sf:any-match (regexp-or-regexps file-name)
  (when regexp-or-regexps
    (let ((regexps (if (listp regexp-or-regexps) regexp-or-regexps (list regexp-or-regexps))))
      (some
       (lambda (re)
         (string-match re file-name))
       regexps))))

(defun* sf:directory-files-recursively (regexp &optional directory type (dir-filter-regexp nil) (exclude-regexps sf:anything-project-exclude-regexps))
  (let* ((directory (or directory default-directory))
         (predfunc (case type
                     (dir 'file-directory-p)
                     (file 'file-regular-p)
                     (otherwise 'identity)))
         (files (directory-files directory t "^[^.]" t))
         (files (mapcar 'ap:follow-symlink files))
         (files (remove-if (lambda (s) (string-match (rx bol (repeat 1 2 ".") eol) s)) files)))
    (loop for file in files
          when (and (funcall predfunc file)
                    (ap:any-match regexp (file-name-nondirectory file))
                    (not (ap:any-match exclude-regexps file)))
          collect file into ret
          when (and (file-directory-p file)
                    (not (ap:any-match dir-filter-regexp file)))
          nconc (ap:directory-files-recursively regexp file type dir-filter-regexp) into ret
          finally return  ret)))

(defun sf:get-module-directory ()
  "return string or nil"
  (let ((cur-dir (sf:current-directory)))
     (when (string-match (rx (group bol (* not-newline) "apps" (+ not-newline) "modules/" (+ (not (any "/"))) "/"))
                         cur-dir)
      (match-string 1 cur-dir))))

(defun sf:relative-files ()
  (let ((module-directory (sf:get-module-directory)))
    (cond
     ((and module-directory (file-directory-p module-directory))
      (sf:directory-files-recursively ".*" module-directory 'file-regular-p nil sf:anything-project-exclude-regexps))
     (t
      (sf:project-files)))))

(defun sf:matched-files (regexp)
    (let ((files (sf:project-files))
          (re (rx-to-string `(and  "/" ,regexp "/"))))
    (remove-if-not (lambda (s) (string-match re s))
                   files)))

(defun sf:get-log-directory ()
  (let ((root-dir (sf:get-project-root)))
  (when root-dir
    (let ((log-dir (sf:catdir root-dir "log/")))
      (when (and log-dir (file-accessible-directory-p log-dir))
        log-dir)))))

;;;; Commands
(defun sf-cmd:all-project-files ()
  (interactive)
  (sf:anything-project (sf:project-files)))

(defun sf-cmd:primary-switch ()
  (interactive)
  (funcall sf:primary-switch-fn))

(defun sf-cmd:relative-files ()
  (interactive)
  (sf:anything-project (sf:relative-files)))

(defun sf-cmd:model-files ()
  (interactive)
  (sf:anything-project (sf:matched-files "model")))

(defun sf-cmd:action-files ()
  (interactive)
  (sf:anything-project (sf:matched-files "actions")))

(defun sf-cmd:template-files ()
  (interactive)
  (sf:anything-project (sf:matched-files "templates")))

(defun sf-cmd:helper-files ()
  (interactive)
  (sf:anything-project (sf:matched-files "helper")))

(defun sf-cmd:test-files ()
  (interactive)
  (sf:anything-project (sf:matched-files "test")))

(defun sf:make-log-buffer-name (log-file)
  (concat "*" log-file "*"))

(defvar sf:number-of-lines-shown-when-opening-log-file 200)

(defun sf:open-log-file (log-file)
  (let ((bufname (sf:make-log-buffer-name log-file)))
    (unless (get-buffer bufname)
      (get-buffer-create bufname)
      (set-buffer bufname)
      (setq auto-window-vscroll t)
      (symfony-minor-mode t)
      (start-process "symfony-tail"
                     bufname
                     "tail"
                     "-n" (format "%d" sf:number-of-lines-shown-when-opening-log-file )
                     "-f"
                     (expand-file-name log-file))
      (current-buffer)
      )))

(defun sf-cmd:open-log-file (log-file)
  (interactive
   (list
    (expand-file-name
    (read-file-name (format "Select log[default: %s]: " sf:previous-log-file)
                    (sf:get-log-directory)
                    sf:previous-log-file
                    t
                    ))))
  (setq sf:previous-log-file log-file)
  (let ((log-buffer  (sf:open-log-file log-file)))
    (switch-to-buffer log-buffer)
    (recenter t)))

;;;; Minor Mode
(defmacro sf:key-with-prefix (key-kbd-sym)
  (let ((key-str (symbol-value key-kbd-sym)))
    `(kbd ,(concat sf:minor-mode-prefix-key " " key-str))))

(defvar sf:minor-mode-map
  (make-sparse-keymap))

(define-minor-mode symfony-minor-mode
  "symfony minor mode"
  nil
  " symfony"
  sf:minor-mode-map)

(defun symfony-minor-mode-maybe ()
  (let ((root-dir (sf:get-project-root)))
    (if root-dir
        (symfony-minor-mode 1)
      (symfony-minor-mode 0))
    ;; specify minor mode on
    (when root-dir
      (let ((minor-mode-name (sf:get-specify-minor-mode-string)))
        (when minor-mode-name
          (funcall (intern minor-mode-name) t))))))

(defun sf:get-specify-minor-mode-string ()
  (let ((type (sf:buffer-type)))
    (when type
      (format "symfony-%s-minor-mode" type))))

(defcustom sf:minor-mode-prefix-key "C-c"
  "Key prefix for symfony minor mode."
  :group 'symfony)

(defun sf:define-key (key-kbd command)
  (assert (commandp command))
  (assert (stringp key-kbd))
  (define-key sf:minor-mode-map (sf:key-with-prefix key-kbd) command))

;;;; Action Minor Mode
;; Prefix: sf-action:
(defvar sf:action-minor-mode-map
  (make-sparse-keymap))

(define-minor-mode symfony-action-minor-mode
  "Symfony Action Minor Mode"
  nil
  " sfAction"
  sf:action-minor-mode-map
  ;; body
  (setq sf:primary-switch-fn 'sf-action:switch-to-template)
  )

(defun sf-action:switch-to-template ()
  (interactive)
  (let ((templates (sf-action:get-templates)))
    (cond
     (templates
      (sf:anything-project templates))
     (t
      (call-interactively 'sf-cmd:all-project-files)))))

(defun sf:take-class-name ()
  (save-excursion
    (goto-char (point-min))
    (let ((class-name-re (rx bol
                          (* space)
                          "class"
                          (+ space)
                          (group
                           (+
                            (or (syntax word) (syntax symbol))))
                          (or space eol))))
        (when (re-search-forward class-name-re nil t)
          (match-string-no-properties 1)))))

(defun sf-action:get-templates ()
  (cond
   ;; actions/actions.class.php
   ((string= (sf:this-file-name) sf:ACTIONS-CLASS-PHP)
    (let ((action-name (sf:take-off-execute (sf:take-function-name))))
      (sf-action:get-templates-by-action-name action-name)))
   ;; fooAction.class.php case
   (t
    (let ((action-name (sf:take-off-action (sf:take-class-name))))
      (sf-action:get-templates-by-action-name action-name)
      ))))

(defun sf-action:get-templates-by-action-name (action-name)
  (when action-name
    (loop for dir in (sf:get-templates-directory)
          nconc (sf:directory-files-recursively
                 (rx-to-string `(and ,action-name "Success.php"))
                 dir))))

;;;; Template Minor Mode
;; Prefix: sf-template:
(defvar sf:template-minor-mode-map
  (make-sparse-keymap))
(define-minor-mode symfony-template-minor-mode
  "Symfony Template Minor Mode"
  nil
  " sfTemplate"
  sf:template-minor-mode-map
  ;; body
  (setq sf:primary-switch-fn 'sf-template:switch-to-action)
  )

(defun sf-template:switch-to-action ()
  (interactive)
  (lexical-let* ((file-name (file-name-sans-extension (sf:this-file-name)))
                 (action-name (sf:take-off-tail-capital file-name)))
    (when action-name
      (lexical-let* ((actions (sf-template:get-specify-actions-by-action-name action-name))
                     (execute-re (rx-to-string
                                  `(and "public"
                                        (+ space)
                                        "function"
                                        (+ space)
                                        "execute"
                                        ,action-name)))
                     (class-re (rx-to-string `(and "class" (+ space) ,action-name "Action"))))
        (let ((sf:after-anything-project-action-hook
               (list
                (lambda ()
                  (goto-char (point-min))
                  (or (re-search-forward execute-re nil t)
                      (re-search-forward class-re nil t))))))
          (sf:anything-project actions))))))

(defun sf-template:get-specify-actions (action-name)
  "return list of string(file name)"
  (sf-template:get-specify-actions-by-action-name action-name))

;; voteSuccess.php -> user/actions/actions.class.php :: executeVote
;; or
;; voteSuccess.php -> user/actions/actions/voteAction.class.php
(defun sf-template:get-specify-actions-by-action-name (action-name)
  (let* ((module-directory (sf:get-module-directory))
         (actions-directory (sf:catdir module-directory "actions")))
    (assert (and actions-directory
                 (file-directory-p actions-directory)))
    (append (sf-template:get-specify-actions-actions-class action-name actions-directory)
            (sf-template:get-specify-actions-saparate-file action-name actions-directory)
            )))

(defun sf-template:get-specify-actions-actions-class (action-name actions-directory)
  "return list"
  (let ((file-path (sf:catdir actions-directory sf:ACTIONS-CLASS-PHP)))
    (when (and file-path (file-exists-p file-path) (file-readable-p file-path))
      (list file-path))))

(defun sf-template:get-specify-actions-saparate-file (action-name actions-directory)
  "return list"
  (let* ((file-name (concat action-name sf:ACTIONS-FILE-RULE))
         (file-path (sf:catdir actions-directory file-name)))
    (when (and file-path (file-exists-p file-path) (file-readable-p file-path))
      (list file-path))))

;;;; Keybinds
(sf:define-key "C-p" 'sf-cmd:primary-switch)
(sf:define-key "<up>" 'sf-cmd:primary-switch)

(sf:define-key "C-n" 'sf-cmd:relative-files)
(sf:define-key "<down>" 'sf-cmd:relative-files)

(sf:define-key "C-c g m" 'sf-cmd:model-files)
(sf:define-key "C-c g a" 'sf-cmd:action-files)
(sf:define-key "C-c g h" 'sf-cmd:helper-files)
(sf:define-key "C-c g t" 'sf-cmd:template-files)
(sf:define-key "C-c g T" 'sf-cmd:test-files)

(sf:define-key "C-c l" 'sf-cmd:open-log-file)


;;;; Install
(defun sf:find-file-hook ()
  (symfony-minor-mode-maybe))
;;; add hook to `find-file-hooks'
(add-hook  'find-file-hooks 'sf:find-file-hook)


;;;; Test
(defmacro* sf:with-file-buffer (file &body body)
  (declare (indent 1))
  `(with-current-buffer (find-file-noselect ,file)
     (prog1 (progn ,@body)
       (kill-buffer (current-buffer)))))

(defun sf:directory-separator ()
  (substring (file-name-as-directory ".") -1))

(defun sf:path-to (path &rest paths)
  (assert (or (null paths)
              (and (listp paths)
                   (stringp (car-safe paths)))))
  (assert (stringp path))
  (let ((paths (append (list path) paths)))
    (concat (file-name-directory (locate-library "symfony"))
            (mapconcat 'identity paths (sf:directory-separator)))))

(defmacro sf:with-php-buffer (s &rest body)
  (declare (indent 1))
  `(with-temp-buffer
     (php-mode)
     (insert ,s)
     (goto-char (point-min))
     (when (re-search-forward (rx "`!!'") nil t)
       (replace-match ""))
     (progn
       ,@body)))

(defmacro sf:with-current-dir (dir &rest body)
  (declare (indent 1))
  `(flet ((sf:current-directory () (file-name-directory ,dir)))
     (progn ,@body)))

(defun sf:askeet-path-to (&rest paths)
  (apply 'sf:path-to "t" "askeet" paths))

(defun sf:to-bool (obj)
  (not (not obj)))

(dont-compile
  (when (fboundp 'expectations)
    (expectations
      (desc "case-fold-search")
      (expect t
        (let ((case-fold-search t))
          (sf:to-bool (string-match "^[A-Z]$" "a"))))
      (expect nil
        (let ((case-fold-search nil))
          (string-match "^[A-Z]$" "a")))

      (desc "sf:path-to")
      (expect "t"
        (file-relative-name (sf:path-to "t")))
      (expect "t/askeet/apps"
        (file-relative-name (sf:path-to "t" "askeet" "apps")))

      (desc "sf:with-current-dir")
      (expect "/hoge/"
        (sf:with-current-dir "/hoge/huga" (sf:current-directory)))

      (desc "sf:askeet-path-to")
      (expect "t/askeet/apps/frontend/modules"
        (file-relative-name (sf:askeet-path-to  "apps" "frontend" "modules")))

      (desc "sf:get-project-root")
      (expect "t/askeet/"
        (file-relative-name 
         (sf:with-current-dir (sf:askeet-path-to  "apps" "frontend" "modules")
           (sf:get-project-root))))

      (desc "sf:take-function-name")
      (expect "executeVote"
        (sf:with-php-buffer "
  public function executeVote()
  {
    $this->answer = AnswerPeer::retrieveByPk($this->getRequestParameter('id'));
    $this->forward404Unless($this->answer);
`!!'
    $user = $this->getUser()->getSubscriber();

    $relevancy = new Relevancy();
    $relevancy->setAnswer($this->answer);
    $relevancy->setUser($user);
    $relevancy->setScore($this->getRequestParameter('score') == 1 ? 1 : -1);
    $relevancy->save();
  }
"
          (sf:take-function-name)))

      (desc "sf:take-off-execute")
      (expect "Vote"
        (sf:take-off-execute "executeVote"))
      
      (expect t
        (stringp (sf:take-off-execute "non-match")))
      
      (expect t
        (stringp (sf:take-off-execute "")))

      (desc "sf:catdir")
      (expect "hoge/huga"
        (sf:catdir "hoge/" "/huga" ))

      (desc "sf:get-templates-directory")
      (expect '("t/askeet/apps/frontend/modules/user/templates")
        (mapcar 'file-relative-name
                (sf:with-current-dir (sf:askeet-path-to "apps/frontend/modules/user/actions" "actions.class.php")
                  (sf:get-templates-directory))))

      (desc "sf:get-templates-file-by-action-name")
      (expect '("t/askeet/apps/frontend/modules/user/templates")
        (mapcar 'file-relative-name
                (sf:with-current-dir (sf:askeet-path-to "apps/frontend/modules/user/actions" "actions.class.php")
                  (sf:get-templates-file-by-action-name "Vote"))))

      (desc "install minor mode")
      (expect t
        (file-exists-p (sf:askeet-path-to "apps/frontend/modules/user/actions" "actions.class.php")))
      (expect t
        (with-current-buffer (find-file-noselect (sf:askeet-path-to "apps/frontend/modules/user/actions" "actions.class.php"))
          (prog1 symfony-minor-mode
            (kill-buffer (current-buffer)))))

      (desc "sf:project-files")
      (expect '("t/askeet/apps/frontend/modules/user" "t/askeet/apps/frontend/modules/tag" "t/askeet/apps/frontend/modules/sidebar" "t/askeet/apps/frontend/modules/question" "t/askeet/apps/frontend/modules/moderator" "t/askeet/apps/frontend/modules/mail" "t/askeet/apps/frontend/modules/feed" "t/askeet/apps/frontend/modules/content" "t/askeet/apps/frontend/modules/api" "t/askeet/apps/frontend/modules/answer" "t/askeet/apps/frontend/modules/administrator")
        (sf:abs->relative
         (sf:with-current-dir (sf:askeet-path-to "apps/frontend/modules/user/actions" "actions.class.php")
           (remove-if-not (lambda (file-name)
                            (string-match (rx "/modules/" (+ (not (any "/"))) eol) file-name))
                          (sf:project-files t)))))

      (desc "sf:get-module-dir-or-root")
      (expect "t/askeet/apps/frontend/modules/"
        (file-relative-name
         (sf:with-current-dir (sf:askeet-path-to "apps/frontend/modules/user/actions" "actions.class.php")
           (sf:get-module-dir-or-root))))

      (expect "t/askeet/"
        (file-relative-name
         (sf:with-current-dir (sf:askeet-path-to "apps/frontend/")
           (sf:get-module-dir-or-root))))


      (desc "sf:buffer-type")
      (expect 'action
        (sf:with-current-dir (sf:askeet-path-to "apps/frontend/modules/user/actions" "actions.class.php")
          (sf:buffer-type)))

      (desc "sf:get-specify-minor-mode-string")
      (expect "symfony-action-minor-mode"
        (sf:with-current-dir (sf:askeet-path-to "apps/frontend/modules/user/actions" "actions.class.php")
          (sf:get-specify-minor-mode-string)))

      (desc "sf:specify-minor-mode-maybe")
      (expect t
        (with-current-buffer (find-file-noselect (sf:askeet-path-to "apps/frontend/modules/user/actions" "actions.class.php"))
          (prog1 symfony-action-minor-mode
            (ignore-errors (kill-buffer (current-buffer))))))

      ;; Test Action
      (desc "sf-action:get-templates")
      (expect '("t/askeet/apps/frontend/modules/user/templates/listInterestedBySuccess.php")
        (sf:abs->relative
         (sf:with-file-buffer (sf:askeet-path-to "apps/frontend/modules/user/actions" "actions.class.php")
           (goto-char (point-min))
           (re-search-forward (rx "public function executeListInterestedBy"))
           (forward-line 3)
           (sf-action:get-templates))))
      (expect '("t/askeet/apps/frontend/modules/user/templates/voteSuccess.php")
        (sf:abs->relative
         (sf:with-file-buffer (sf:askeet-path-to "apps/frontend/modules/user/actions" "voteAction.class.php")
           (re-search-forward (rx "public function execute") nil t)
           (sf-action:get-templates))))

      (desc "sf:get-module-directory")
      (expect "t/askeet/apps/frontend/modules/user/"
        (file-relative-name
         (sf:with-file-buffer (sf:askeet-path-to "apps/frontend/modules/user/templates/voteSuccess.php")
           (sf:get-module-directory))))

      (desc "sf:take-off-tail-capital")
      (expect "passwordRequest"
        (sf:take-off-tail-capital "passwordRequestSuccess"))
      (expect "vote"
        (sf:take-off-tail-capital "voteSuccess"))
      (expect nil
        (sf:take-off-tail-capital "lowercase"))

      (desc "sf-template:get-specify-actions-by-action-name")
      (expect '("t/askeet/apps/frontend/modules/user/actions/actions.class.php" "t/askeet/apps/frontend/modules/user/actions/voteAction.class.php")
        (sf:abs->relative
         (sf:with-file-buffer (sf:askeet-path-to "apps/frontend/modules/user/templates/voteSuccess.php")
           (sf-template:get-specify-actions-by-action-name "vote"))))
      (desc "sf-template:switch-to-action")
      (expect t
        (sf:to-bool
         (string-match (rx "public function executeInterested()")
                       (sf:with-file-buffer (sf:askeet-path-to "apps/frontend/modules/user/templates/interestedSuccess.php")
                         (call-interactively 'sf-template:switch-to-action)
                         (buffer-substring-no-properties (point-at-bol) (point-at-eol))))))

      (desc "sf:relative-files")
      (expect '("t/askeet/apps/frontend/modules/user/validate" "t/askeet/apps/frontend/modules/user/validate/update.yml" "t/askeet/apps/frontend/modules/user/validate/passwordRequest.yml" "t/askeet/apps/frontend/modules/user/validate/login.yml" "t/askeet/apps/frontend/modules/user/validate/add.yml" "t/askeet/apps/frontend/modules/user/templates" "t/askeet/apps/frontend/modules/user/templates/voteSuccess.php" "t/askeet/apps/frontend/modules/user/templates/showSuccess.php" "t/askeet/apps/frontend/modules/user/templates/reportQuestionSuccess.php" "t/askeet/apps/frontend/modules/user/templates/reportAnswerSuccess.php" "t/askeet/apps/frontend/modules/user/templates/passwordRequestSuccess.php" "t/askeet/apps/frontend/modules/user/templates/passwordRequestMailSent.php" "t/askeet/apps/frontend/modules/user/templates/loginSuccess.php" "t/askeet/apps/frontend/modules/user/templates/listInterestedBySuccess.php" "t/askeet/apps/frontend/modules/user/templates/interestedSuccess.php"  "t/askeet/apps/frontend/modules/user/lib" "t/askeet/apps/frontend/modules/user/config" "t/askeet/apps/frontend/modules/user/config/view.yml" "t/askeet/apps/frontend/modules/user/config/security.yml" "t/askeet/apps/frontend/modules/user/actions" "t/askeet/apps/frontend/modules/user/actions/voteAction.class.php" "t/askeet/apps/frontend/modules/user/actions/actions.class.php")
        (sf:abs->relative
         (sf:with-file-buffer (sf:askeet-path-to "apps/frontend/modules/user/actions" "voteAction.class.php")
           (sf:relative-files))))

      (desc "sf:get-log-directory")
      (expect "t/askeet/log"
        (file-relative-name
         (sf:with-file-buffer (sf:askeet-path-to "apps/frontend/modules/user/actions" "voteAction.class.php")
           (sf:get-log-directory))))
      )))


(provide 'symfony)
;; symfony.el ends here.