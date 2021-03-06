(in-package :cl-user)
(defpackage shelly.core
  (:use :cl)
  (:shadow :read :print)
  (:import-from :cl-fad
                :file-exists-p)
  (:import-from :trivial-signal
                :signal-handler
                :signal-name)
  (:import-from :bordeaux-threads
                :all-threads
                :thread-alive-p
                :join-thread)
  (:import-from :shelly.impl
                :condition-undefined-function-name)
  (:import-from :shelly.error
                :shelly-error
                :shelly-read-error
                :shelly-command-not-found-error)
  (:import-from :shelly.util
                :with-retrying-when-system-not-found
                :terminate)
  (:export :*argv*
           :interpret
           :run-repl))
(in-package :shelly.core)

(defparameter *argv* '())

(defun shelly.core::read (expr)
  (let ((*package* (find-package :cl-user)))
    (destructuring-bind (fn &rest args) expr
      (cons (handler-case (if (stringp fn)
                              (read-from-string fn)
                              fn)
              (error (c)
                (error 'shelly-read-error
                       :expression expr
                       :format-control (princ-to-string c))))
            (mapcar #'canonicalize-arg
                    args)))))

(defun shelly.core::print (result)
  (fresh-line)
  (prin1 result))

(defun interpret (expr &key verbose)
  (pushnew :shelly *features*)
  (when verbose
    (format *debug-io* "~&;-> ~S~%" expr))

  (let (retval)
    (handler-case
        (let ((expr (shelly.core::read expr))
              (system-threads #+thread-support (bt:all-threads)
                              #-thread-support nil))
          (labels ((alive-user-threads ()
                     (remove-if-not #'bt:thread-alive-p
                                    (set-difference
                                     #+thread-support (bt:all-threads)
                                     #-thread-support nil
                                     system-threads)))
                   (wait-user-threads ()
                     (let
                         #+ccl ((ccl::*invoke-debugger-hook-on-interrupt* t)
                                (*debugger-hook* (lambda () (ccl:quit))))
                       #-ccl ()
                       (map nil #'bt:join-thread (alive-user-threads)))))

            (setf (signal-handler :int)
                  #'(lambda (signo)
                      (terminate 1 "~&SIG~A~%" (signal-name signo))))

            (when verbose
              (format *debug-io* "~&;-> ~S~%" expr))

            (let ((result
                    (multiple-value-list
                     (handler-case (let ((*package* (find-package :cl-user)))
                                     (with-retrying-when-system-not-found
                                       (eval expr)))
                       (undefined-function (c)
                         (let ((funcname (condition-undefined-function-name c)))
                           (if (string-equal funcname (car expr))
                               (error 'shelly-command-not-found-error
                                      :command funcname)
                               (error c))))))))
              #+clisp
              (setf retval (car result))
              #-clisp
              (when result
                (shelly.core::print (car result))
                (fresh-line)))

            (handler-case (wait-user-threads)
              (condition (e)
                (princ e)
                (terminate)))))
      (shelly-command-not-found-error (e)
        (format *error-output* "~&Error: ~A~%" e)))
    (setf *features* (remove :shelly *features* :test #'eq))
    retval))

(defun prompt ()
  (fresh-line)
  (princ "> ")
  (force-output))

(defun run-repl (&key verbose)
  "Start Read-Eval-Print Loop for interactive execution."
  (prompt)
  (loop for expr = (read-line *terminal-io* nil :eof)
        until (eq expr :eof)
        do (unwind-protect
               (unless (string= "" expr)
                 (interpret
                  (mapcar #'prin1-to-string
                          (read-from-string (concatenate 'string "(" expr ")")))
                  :verbose verbose))
             (run-repl))
           (prompt)
        finally (terminate)))

(defun canonicalize-arg (arg0)
  (unless (stringp arg0)
    (return-from canonicalize-arg arg0))

  (let* ((errorp nil)
         (arg (handler-case (let ((*package* (find-package :cl-user)))
                              (read-from-string arg0))
                (error ()
                  (setf errorp t)
                  arg0))))
    (cond
      ((and (not errorp)
            (not (symbolp arg))) arg)
      ((string= "" arg) arg)
      ((string= "--" (handler-case (subseq (string arg) 0 2)
                       (error ())))
       (intern (subseq (string arg) 2)
               :keyword))
      ((ignore-errors (fad:file-exists-p arg0)))
      ((and (not (keywordp arg))
            (symbolp arg)
            (string= (package-name (symbol-package arg)) :common-lisp-user))
       (string arg0))
      (t arg))))
