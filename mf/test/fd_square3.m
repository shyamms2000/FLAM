% Five-point stencil on the unit square, constant-coefficient Helmholtz
% equation, Dirichlet boundary conditions.
%
% This is basically the same as FD_SQUARE1 but for the Helmholtz equation. The
% resulting matrix is square, real, and symmetric (at general frequency).

function fd_square3(n,k,occ,symm,doiter,diagmode)

  % set default parameters
  if nargin < 1 || isempty(n), n = 128; end  % number of points + 1 in each dim
  if nargin < 2 || isempty(k), k = 2*pi*8; end  % wavenumber
  if nargin < 3 || isempty(occ), occ = 8; end
  if nargin < 4 || isempty(symm), symm = 'h'; end  % symmetric/Hermitian
  if nargin < 5 || isempty(doiter), doiter = 1; end  % unpreconditioned GMRES?
  if nargin < 6 || isempty(diagmode), diagmode = 0; end  % diag extraction mode:
  % 0 - skip; 1 - matrix unfolding; 2 - sparse apply/solves

  % initialize
  N = (n - 1)^2;  % total number of grid points
  h = 1/n;        % mesh width

  % set up sparse matrix
  idx = zeros(n+1,n+1);  % index mapping to each point, including "ghost" points
  idx(2:n,2:n) = reshape(1:N,n-1,n-1);
  mid = 2:n;    % "middle" indices -- interaction with self
  lft = 1:n-1;  % "left"   indices -- interaction with one below
  rgt = 3:n+1;  % "right"  indices -- interaction with one above
  I = idx(mid,mid); e = ones(size(I));
  % interactions with ...
  Jl = idx(lft,mid); Sl = -e;                                % ... left
  Jr = idx(rgt,mid); Sr = -e;                                % ... right
  Ju = idx(mid,lft); Su = -e;                                % ... up
  Jd = idx(mid,rgt); Sd = -e;                                % ... down
  Jm = idx(mid,mid); Sm = -(Sl + Sr + Su + Sd) - h^2*k^2*e;  % ... middle (self)
  % combine all interactions
  I = [ I(:);  I(:);  I(:);  I(:);  I(:)];
  J = [Jl(:); Jr(:); Ju(:); Jd(:); Jm(:)];
  S = [Sl(:); Sr(:); Su(:); Sd(:); Sm(:)];
  % remove ghost interactions
  idx = find(J > 0); I = I(idx); J = J(idx); S = S(idx);
  A = sparse(I,J,S,N,N);
  clear idx Jl Sl Jr Sr Ju Su Jd Sd Jm Sm I J S

  % factor matrix
  opts = struct('symm',symm,'verb',1);
  tic; F = mf2(A,n,occ,opts); t = toc;
  w = whos('F'); mem = w.bytes/1e6;
  fprintf('mf2 time/mem: %10.4e (s) / %6.2f (MB)\n',t,mem)

  % test accuracy using randomized power method
  X = rand(N,1);
  X = X/norm(X);

  % NORM(A - F)/NORM(A)
  tic; mf_mv(F,X); t = toc;  % for timing
  err = snorm(N,@(x)(A*x - mf_mv(F,x)),[],[],1);
  err = err/snorm(N,@(x)(A*x),[],[],1);
  fprintf('mf_mv: %10.4e / %10.4e (s)\n',err,t)

  % NORM(INV(A) - INV(F))/NORM(INV(A)) <= NORM(I - A*INV(F))
  tic; mf_sv(F,X); t = toc;  % for timing
  err = snorm(N,@(x)(x - A*mf_sv(F,x)),@(x)(x - mf_sv(F,A*x,'c')));
  fprintf('mf_sv: %10.4e / %10.4e (s)\n',err,t)

  % run unpreconditioned GMRES
  B = A*X;
  iter(1:2) = nan;
  if doiter, [~,~,~,iter] = gmres(@(x)(A*x),B,32,1e-12,32); end

  % run preconditioned GMRES
  tic; [Y,~,~,piter] = gmres(@(x)(A*x),B,32,1e-12,32,@(x)mf_sv(F,x)); t = toc;
  err1 = norm(X - Y)/norm(X);
  err2 = norm(B - A*Y)/norm(B);
  fprintf('gmres:\n')
  fprintf('  soln/resid err/time: %10.4e / %10.4e / %10.4e (s)\n',err1,err2,t)
  fprintf('  precon/unprecon iter: %d / %d\n',(piter(1)+1)*piter(2), ...
          (iter(1)+1)*iter(2))

  % compute log-determinant
  tic
  ld = mf_logdet(F);
  t = toc;
  fprintf('mf_logdet: %22.16e / %10.4e (s)\n',ld,t)

  if diagmode > 0
    % prepare for diagonal extraction
    opts = struct('verb',1);
    m = min(N,128);  % number of entries to check against
    r = randperm(N); r = r(1:m);
    % reference comparison from compressed solve against coordinate vectors
    X = zeros(N,m);
    for i = 1:m, X(r(i),i) = 1; end
    E = zeros(m,1);  % solution storage
    if diagmode == 1, fprintf('mf_diag:\n')
    else,             fprintf('mf_spdiag:\n')
    end

    % extract diagonal
    tic;
    if diagmode == 1, D = mf_diag(F,0,opts);
    else,             D = mf_spdiag(F);
    end
    t = toc;
    Y = mf_mv(F,X);
    for i = 1:m, E(i) = Y(r(i),i); end
    err = norm(D(r) - E)/norm(E);
    fprintf('  fwd: %10.4e / %10.4e (s)\n',err,t)

    % extract diagonal of inverse
    tic;
    if diagmode == 1, D = mf_diag(F,1,opts);
    else,             D = mf_spdiag(F,1);
    end
    t = toc;
    Y = mf_sv(F,X);
    for i = 1:m, E(i) = Y(r(i),i); end
    err = norm(D(r) - E)/norm(E);
    fprintf('  inv: %10.4e / %10.4e (s)\n',err,t)
  end
end