% RSKELF_DIAG  Extract diagonal using recursive skeletonization factorization
%              via matrix unfolding.
%
%    This is a variant of the selected inversion algorithm for sparse matrices
%    via the multifrontal factorization, generalized to account for additional
%    ID-based sparsification operators. The point is that only a sparse subset
%    of all matrix entries need to be reconstructed from the top-level
%    skeletons in order to compute the diagonal.
%
%    Typical complexity: same as RSKELF.
%
%    D = RSKELF_DIAG(F) produces the diagonal D of the factored matrix F.
%
%    D = RSKELF_DIAG(F,DINV) computes D = DIAG(F) if DINV = 0 (default) and
%    D = DIAG(INV(F)) if DINV = 1.
%
%    D = RSKEL_DIAG(F,DINV,OPTS) also passes various options to the algorithm.
%    Valid options include:
%
%      - VERB: display status info if VERB = 1 (default: VERB = 0). This prints
%              to screen a table tracking extraction statistics through
%              factorization level (i.e., tree leaves are at level 1). Special
%              levels: 'A', for determining all required entries to compute.
%
%    Related references:
%
%      L. Lin, J. Lu, L. Ying, R. Car, W. E. Fast algorithm for extracting the
%        diagonal of the inverse matrix with application to the electronic
%        structure analysis of metallic systems. Commun. Math. Sci. 7 (3):
%        755-777, 2009.
%
%    See also MF_DIAG, RSKELF, RSKELF_SPDIAG.

function D = rskelf_diag(F,dinv,opts)

  % set default parameters
  if nargin < 2, dinv = 0; end
  if nargin < 3, opts = []; end
  if ~isfield(opts,'verb'), opts.verb = 0; end

  if opts.verb
    fprintf([repmat('-',1,31) '\n'])
    fprintf('%3s | %12s | %10s\n','lvl','nnz kept','time (s)')
    fprintf([repmat('-',1,31) '\n'])
  end

  % initialize
  N = F.N;
  nlvl = F.nlvl;
  rem = true(N,1);   % which points remain?
  mnz = N;           % maximum capacity for sparse matrix workspace
  I = zeros(mnz,1);  % sparse matrix worksapce
  J = zeros(mnz,1);

  % find required entries at each level
  ts = tic;
  keep = cell(nlvl,1);  % entries to keep after unfolding at each level
  keep{1} = sparse(1:N,1:N,true(N,1),N,N);  % at leaf, just need diagonal
  for lvl = 1:nlvl-1  % current level is lvl+1
    nz = 0;

    % eliminate redundant indices
    rem([F.factors(F.lvp(lvl)+1:F.lvp(lvl+1)).rd]) = 0;

    % keep entries needed directly by previous level
    [I_,J_] = find(keep{lvl});
    idx = rem(I_) & rem(J_);
    I_ = I_(idx);
    J_ = J_(idx);
    m = numel(I_);
    nz_new = nz + m;
    if mnz < nz_new
      while mnz < nz_new, mnz = 2*mnz; end
      e = zeros(mnz-length(I),1);
      I = [I; e];
      J = [J; e];
    end
    I(nz+1:nz+m) = I_;
    J(nz+1:nz+m) = J_;
    nz = nz + m;

    % loop over nodes at previous level
    for i = F.lvp(lvl)+1:F.lvp(lvl+1)

      % keep skeleton entries
      sk = F.factors(i).sk;
      [I_,J_] = ndgrid(sk);
      m = numel(I_);
      nz_new = nz + m;
      if mnz < nz_new
        while mnz < nz_new, mnz = 2*mnz; end
        e = zeros(mnz-length(I),1);
        I = [I; e];
        J = [J; e];
      end
      I(nz+1:nz+m) = I_;
      J(nz+1:nz+m) = J_;
      nz = nz + m;
    end

    % construct requirement matrix
    idx = 1:nz;
    if ~strcmpi(F.symm,'n'), idx = find(I(idx) >= J(idx)); end
    keep{lvl+1} = sparse(I(idx),J(idx),true(size(idx)),N,N);
  end
  t = toc(ts);

  % print summary
  if opts.verb
    keep_ = keep{1};
    for lvl = 1:nlvl-1, keep_ = keep_ | keep{lvl+1}; end
    fprintf('%3s | %12d | %10.2e\n','a',nnz(keep_),t)
  end

  % unfold factorization
  S = zeros(mnz,1);
  M = sparse(N,N);  % successively unfolded matrix
  for lvl = nlvl:-1:1  % loop from top-down
    ts = tic;

    % find all existing entries
    [I_,J_,S_] = find(M);
    nz = length(S_);
    I(1:nz) = I_;
    J(1:nz) = J_;
    S(1:nz) = S_;

    % loop over nodes
    for i = F.lvp(lvl)+1:F.lvp(lvl+1)
      sk = F.factors(i).sk;
      rd = F.factors(i).rd;
      T = F.factors(i).T;
      L = F.factors(i).L;
      E = F.factors(i).E;
      if strcmpi(F.symm,'n') || strcmpi(F.symm,'s')
        G = F.factors(i).F;
        U = F.factors(i).U;
      else
        G = F.factors(i).E';
        U = F.factors(i).L';
      end

      % unfold local factorization
      nrd = length(rd);
      nsk = length(sk);
      ird = 1:nrd;
      isk = nrd+(1:nsk);
      X = zeros(nrd+nsk);
      % redundant part
      if strcmpi(F.symm,'h')
        if dinv, X(ird,ird) = inv(F.factors(i).U);
        else,    X(ird,ird) =     F.factors(i).U ;
        end
      else
        X(ird,ird) = eye(nrd);
      end
      % skeleton part
      Xsk = spget(M,sk,sk);
      if nsk && ~strcmpi(F.symm,'n')
        D_ = diag(diag(Xsk));
        L_ = tril(Xsk,-1);
        U_ = triu(Xsk, 1);
        if strcmpi(F.symm,'s'), Xsk = D_ + L_ + L_.' + U_ + U_.';
        else,                   Xsk = D_ + L_ + L_'  + U_ + U_' ;
        end
      end
      X(isk,isk) = Xsk;
      % undo elimination and sparsification operators
      if dinv
        X(:,ird) = (X(:,ird) - X(:,isk)*E)/L;
        X(ird,:) = U\(X(ird,:) - G*X(isk,:));
      else
        X(:,isk) = X(:,isk) + X(:,ird)*G;
        X(isk,:) = X(isk,:) + E*X(ird,:);
      end
      if dinv
        if strcmp(F.symm,'s'), X(:,isk) = X(:,isk) - X(:,ird)*T.';
        else,                  X(:,isk) = X(:,isk) - X(:,ird)*T' ;
        end
        X(isk,:) = X(isk,:) - T*X(ird,:);
      else
        X(:,ird) = X(:,ird)*U + X(:,isk)*T;
        if strcmp(F.symm,'s'), X(ird,:) = L*X(ird,:) + T.'*X(isk,:);
        else,                  X(ird,:) = L*X(ird,:) + T' *X(isk,:);
        end
      end
      X(isk,isk) = X(isk,isk) - Xsk;  % to be stored as update

      % store update to global sparse matrix
      [I_,J_] = ndgrid([rd sk]);
      m = numel(X);
      nz_new = nz + m;
      if mnz < nz_new
        while mnz < nz_new, mnz = 2*mnz; end
        e = zeros(mnz-length(I),1);
        I = [I; e];
        J = [J; e];
        S = [S; e];
      end
      I(nz+1:nz+m) = I_;
      J(nz+1:nz+m) = J_;
      S(nz+1:nz+m) = X ;
      nz = nz + m;
    end

    % update unfolded sparse matrix
    M = sparse(I(1:nz),J(1:nz),S(1:nz),N,N) .* keep{lvl};
    t = toc(ts);

    % print summary
    if opts.verb, fprintf('%3d | %12d | %10.2e\n',lvl,nnz(keep{lvl}),t); end
  end

  % finish
  D = spdiags(M,0);
  if opts.verb, fprintf([repmat('-',1,31) '\n']); end
end