
% M= obj.M_M;
% f= rand(size(M,1),1);
% 
% [U,D,V]= svd(M);
% 
% U'*M*pinv(M)*U
% all( all( abs(U'*M*pinv(M)*U - eye(size(M))) < 1e-7 ) )

% all( all( abs(U'*U - eye(size(U))) < 1e-7 ) )

% all( all( abs( M*pinv(M) - eye(size(M)) ) < 1e-5 ) )
% 
% D_full= D(1:rank(M),1:rank(M));
% U_full= U(:,1:rank(M));
% U_0= U(:,rank(M)+1:end);

% all( all( abs(M*pinv(M) - eye(size(M))) < 1e-7 ) )
% all( all( abs(pinv(M)*M - eye(size(M))) < 1e-7 ) )

% all( all( abs(U_full*U_full' + U_0*U_0' - eye(size(U,1))) < 1e-7 ) )

% all( all( abs(U_full'*U_full - eye(size(U_full'*U_full))) < 1e-7 ) )

% [Q,R]= qr(M);


% all( all( abs( Q'*Q - eye(size(Q)) ) < 1e-5 ) )

% rank(R);

% all(all(M - M' < 1e-5))


% f'*M*f
% 
% sqrt_M= U_full*sqrt(D_full)*U_full';
% norm( (sqrt_M*f) )^2;
% norm( sqrt(D_full)* U_full' * f )^2


%%

I= 1e-8;
n= 14;
P= 1e-5;

for r= 1:n
    if  (P*n)^r  / factorial(r)  < I
        break
    end
end
n_max= r - 1;


n_max

n_H= 0;
for i= 1:n_max
    n_H= n_H + nchoosek(n, i);
end

n_H

%%

clear; clc; close all;

x = [-3:.1:3];
norm = normpdf(x,0,1);

figure;
plot(x,norm, 'linewidth', 2)

%%

x_values= 0:0.001:20;
figure; hold on; grid on;

plot(x_values, obj.optimization_fn(...
              x_values, fx_hat_dir, M_dir, obj.sigma_hat, params.alert_limit, params.m_F * obj.n_L_M))



%%

clear; clc;

a= cell(1,9);

b= [1,2,3; 1,2,3];
a(1,1:size(b,2))= num2cell(b,1) 
a(1, size(b,2) + 1:size(b,2) + size(b,2))= num2cell(b,1) 
















