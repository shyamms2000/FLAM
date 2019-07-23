% Covariance matrix on the unit circle, squared exponential kernel.
%
% This is essentially the same as COV_LINE1 but on the circle instead of the
% line. The resulting matrix is square, real, positive definite, and circulant.

function cov_circle1(n,occ,p,rank_or_tol,symm,noise,scale,spdiag)

  % set default parameters
  if nargin < 1 || isempty(n), n = 16384; end  % number of points
  if nargin < 2 || isempty(occ), occ = 64; end
  if nargin < 3 || isempty(p), p = 16; end  % sqrt number of proxy points
  if nargin < 4 || isempty(rank_or_tol), rank_or_tol = 1e-12; end
  if nargin < 5 || isempty(symm), symm = 'p'; end  % positive definite
  if nargin < 6 || isempty(noise), noise = 1e-2; end  % nugget effect
  if nargin < 7 || isempty(scale), scale = 100; end  % kernel length scale
  if nargin < 8 || isempty(spdiag), spdiag = 0; end  % sparse diag extraction?

  % initialize
  theta = (1:n)*2*pi/n; x = [cos(theta); sin(theta)];  % row/col points
  N = size(x,2);
  % proxy points -- a few concentric rings
  theta = (1:p)*2*pi/p; proxy_ = [cos(theta); sin(theta)];  % base ring
  proxy = [];  % accumulate several rings
  for r = linspace(1.5,2.5,p), proxy = [proxy r*proxy_]; end
  % reference proxy points are for unit box [-1, 1]^2

  % factor matrix
  Afun = @(i,j)Afun2(i,j,x,noise,scale);
  pxyfun = @(x,slf,nbr,l,ctr)pxyfun2(x,slf,nbr,l,ctr,proxy,scale);
  opts = struct('symm',symm,'verb',1);
  tic; F = rskelf(Afun,x,occ,rank_or_tol,pxyfun,opts); t = toc;
  w = whos('F'); mem = w.bytes/1e6;
  fprintf('rskelf time/mem: %10.4e (s) / %6.2f (MB)\n',t,mem)

  % set up reference FFT multiplication
  G = fft(Afun(1:N,1));
  mv = @(x)mv2(G,x);

  % test accuracy using randomized power method
  X = rand(N,1);
  X = X/norm(X);

  % NORM(A - F)/NORM(A)
  tic; rskelf_mv(F,X); t = toc;  % for timing
  err = snorm(N,@(x)(mv(x) - rskelf_mv(F,x)),[],[],1);
  err = err/snorm(N,mv,[],[],1);
  fprintf('rskel_mv err/time: %10.4e / %10.4e (s)\n',err,t)

  % NORM(INV(A) - INV(F))/NORM(INV(A)) <= NORM(I - A*INV(F))
  tic; rskelf_sv(F,X); t = toc;  % for timing
  err = snorm(N,@(x)(x - mv(rskelf_sv(F,x))),@(x)(x - rskelf_sv(F,mv(x),'c')));
  fprintf('rskel_sv err/time: %10.4e / %10.4e (s)\n',err,t)

  % test Cholesky accuracy -- error is w.r.t. compressed apply/solve
  if strcmpi(symm,'p')
    % NORM(F - C*C')/NORM(F)
    tic; rskelf_cholmv(F,X); t = toc;  % for timing
    err = snorm(N,@(x)(rskelf_mv(F,x) ...
                         - rskelf_cholmv(F,rskelf_cholmv(F,x,'c'))),[],[],1);
    err = err/snorm(N,@(x)(rskelf_mv(F,x)),[],[],1);
    fprintf('rskelf_cholmv: %10.4e / %10.4e (s)\n',err,t)

    % NORM(INV(F) - INV(C')*INV(C))/NORM(INV(F))
    tic; rskelf_cholsv(F,X); t = toc;  % for timing
    err = snorm(N,@(x)(rskelf_sv(F,x) ...
                         - rskelf_cholsv(F,rskelf_cholsv(F,x),'c')),[],[],1);
    err = err/snorm(N,@(x)(rskelf_sv(F,x)),[],[],1);
    fprintf('rskelf_cholsv: %10.4e / %10.4e (s)\n',err,t)
  end

  % compute log-determinant
  tic; ld = rskelf_logdet(F); t = toc;
  fprintf('rskelf_logdet: %22.16e / %10.4e (s)\n',ld,t)

  % prepare for diagonal extraction
  opts = struct('verb',1);
  m = min(N,128);  % number of entries to check against
  r = randperm(N); r = r(1:m);
  % reference comparison from compressed solve against coordinate vectors
  X = zeros(N,m);
  for i = 1:m, X(r(i),i) = 1; end
  E = zeros(m,1);  % solution storage
  if spdiag, fprintf('rskelf_spdiag:\n')
  else,      fprintf('rskelf_diag:\n')
  end

  % extract diagonal
  tic;
  if spdiag, D = rskelf_spdiag(F);
  else,      D = rskelf_diag(F,0,opts);
  end
  t = toc;
  Y = rskelf_mv(F,X);
  for i = 1:m, E(i) = Y(r(i),i); end
  err = norm(D(r) - E)/norm(E);
  fprintf('  fwd: %10.4e / %10.4e (s)\n',err,t)

  % extract diagonal of inverse
  tic;
  if spdiag, D = rskelf_spdiag(F,1);
  else,      D = rskelf_diag(F,1,opts);
  end
  t = toc;
  Y = rskelf_sv(F,X);
  for i = 1:m, E(i) = Y(r(i),i); end
  err = norm(D(r) - E)/norm(E);
  fprintf('  inv: %10.4e / %10.4e (s)\n',err,t)
end

% kernel function
function K = Kfun(x,y,scale)
  dx = bsxfun(@minus,x(1,:)',y(1,:));
  dy = bsxfun(@minus,x(2,:)',y(2,:));
  dr = scale*sqrt(dx.^2 + dy.^2);  % scaled distance
  K = exp(-0.5*dr.^2);
end

% matrix entries
function A = Afun2(i,j,x,noise,scale)
  A = Kfun(x(:,i),x(:,j),scale);
  [I,J] = ndgrid(i,j);
  idx = I == J;
  A(idx) = A(idx) + noise^2;  % modify diagonal with "nugget"
end

% proxy function
function [Kpxy,nbr] = pxyfun2(x,slf,nbr,l,ctr,proxy,scale)
  pxy = bsxfun(@plus,proxy*l,ctr');  % scale and translate reference points
  Kpxy = Kfun(pxy,x(:,slf),scale);
  dx = x(1,nbr) - ctr(1);
  dy = x(2,nbr) - ctr(2);
  % proxy points form interval of scaled radius 1.5 around current box
  % keep among neighbors only those within interval
  dist = sqrt(dx.^2 + dy.^2);
  nbr = nbr(dist/l < 1.5);
end

% FFT multiplication
function y = mv2(F,x)
  y = ifft(F.*fft(x));
end